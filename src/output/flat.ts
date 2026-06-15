import type { BundleGraph, ResolvedConfig } from "../types.js";
import {
  buildRequireHelper,
  lightMinify,
  makeVarName,
  metadataBanner,
  moduleComment,
  replaceRequires,
} from "./shared.js";

/** Error when flat mode hits a circular require (cannot be handled flatly). */
export function assertFlatable(graph: BundleGraph): void {
  if (graph.cycles.length === 0) return;
  const detail = graph.cycles
    .map((cycle) => "    " + cycle.join(" -> "))
    .join("\n");
  throw new Error(
    `flat mode cannot handle circular requires — found ${graph.cycles.length} cycle(s):\n${detail}\n` +
      `  fix: use mode "runtime" or break the circular dependency`,
  );
}

/**
 * Flat mode:
 * - order modules dependency-first (deps before importers)
 * - each module = local var = (function() ... end)()
 * - require("dep") is replaced by its local var directly, no runtime loader
 * - root code goes last
 */
export function generateFlat(
  graph: BundleGraph,
  config: ResolvedConfig,
): string {
  assertFlatable(graph);

  const used = new Set<string>();
  // map path -> local var name
  const varByPath = new Map<string, string>();
  let index = 0;
  for (const path of graph.order) {
    if (path === graph.rootPath) continue;
    varByPath.set(path, makeVarName(path, index++, used));
  }

  const requireHelper = buildRequireHelper(config);
  let usedRequireHelper = false;

  // map module name -> var (via each node's deps)
  const body: string[] = [];

  for (const path of graph.order) {
    const node = graph.modules.get(path);
    if (!node) continue;

    // resolver: module name -> var name (bundled dep) or __lf_require (ignored/dynamic)
    const nameToVar = new Map<string, string>();
    for (const dep of node.deps) {
      const depVar = varByPath.get(dep.path);
      if (depVar) nameToVar.set(dep.name, depVar);
    }
    const transformed = replaceRequires(node, (call) => {
      const depVar = nameToVar.get(call.name);
      if (depVar) {
        if (call.statementRange) {
          return {
            replacement: depVar,
            statementReplacement: "",
          };
        }
        return depVar;
      }
      // require that is not bundled (ignored) -> go through helper, never keep raw global require
      usedRequireHelper = true;
      return requireHelper.call(call.name);
    }).trim();

    if (path === graph.rootPath) {
      const comment = moduleComment(config, path, "root");
      body.push((comment ? comment + "\n" : "") + transformed);
    } else {
      const varName = varByPath.get(path)!;
      const comment = moduleComment(config, path, "module");
      const block =
        (comment ? comment + "\n" : "") +
        `local ${varName} = (function()\n${indent(transformed)}\nend)()`;
      body.push(block);
    }
  }

  const head: string[] = [];
  const banner = metadataBanner(graph, config);
  if (banner) head.push(banner.trimEnd());
  if (usedRequireHelper) head.push(requireHelper.decl);

  // separate blocks with a single blank line — debug-readable, no excess blanks
  const code = [...head, ...body].join("\n\n") + "\n";
  return config.minify ? lightMinify(code) : code;
}

function indent(source: string): string {
  return source
    .split("\n")
    .map((line) => (line.length > 0 ? "  " + line : line))
    .join("\n");
}
