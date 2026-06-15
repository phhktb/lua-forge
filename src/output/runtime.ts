import type { BundleGraph, ResolvedConfig } from "../types.js";
import {
  buildRequireHelper,
  lightMinify,
  luaString,
  metadataBanner,
  moduleComment,
  REQUIRE_HELPER,
} from "./shared.js";

const ROOT_KEY = "__lua_forge_root__";

/**
 * Runtime mode:
 * - register each module as a factory function
 * - __bundle_require: fast path for already-loaded modules
 * - localize frequently used globals (type/tostring/error) to cut global lookups
 * - supports circular require: set entry before running the factory (returns partial, like normal Lua)
 * - ignored / dynamic require -> __lf_require (FiveM: clear error, no global require dependency)
 */
export function generateRuntime(
  graph: BundleGraph,
  config: ResolvedConfig,
): string {
  const head: string[] = [];
  const banner = metadataBanner(graph, config);
  if (banner) head.push(banner.trimEnd());

  const requireHelper = buildRequireHelper(config);

  // runtime loader — minimal boilerplate, fast path first
  const loader = [
    requireHelper.decl,
    `local error, type, tostring = error, type, tostring`,
    `local __modules = {}`,
    `local __loaded = {}`,
    `local function __bundle_require(name)`,
    `  local entry = __loaded[name]`,
    `  if entry then return entry.value end`,
    `  local factory = __modules[name]`,
    `  if not factory then return ${REQUIRE_HELPER}(name) end`,
    `  entry = { value = true }`,
    `  __loaded[name] = entry`,
    `  local result = factory(__bundle_require)`,
    `  if result ~= nil then entry.value = result end`,
    `  return entry.value`,
    `end`,
  ].join("\n");
  head.push(loader);

  const blocks: string[] = [];
  // register modules in load order (dependency-first); root is registered under a special key
  for (const path of graph.order) {
    const node = graph.modules.get(path);
    if (!node) continue;

    // root must also be registered under its real names, not only ROOT_KEY
    // (for the circular case where another module requires the root back)
    const names = node.isRoot ? [ROOT_KEY, ...node.names] : [...node.names];
    if (names.length === 0) continue;

    const comment = moduleComment(config, path, node.isRoot ? "root" : "module");
    const lines: string[] = [];
    if (comment) lines.push(comment);
    lines.push(`__modules[${luaString(names[0])}] = function(require)`);
    lines.push(indent(node.source.trim()));
    lines.push(`end`);
    // one factory shared across all names pointing to the same file
    for (let i = 1; i < names.length; i++) {
      lines.push(
        `__modules[${luaString(names[i])}] = __modules[${luaString(names[0])}]`,
      );
    }
    blocks.push(lines.join("\n"));
  }

  const footer = `return __bundle_require(${luaString(ROOT_KEY)})`;
  const code = [...head, ...blocks, footer].join("\n\n") + "\n";
  return config.minify ? lightMinify(code) : code;
}

function indent(source: string): string {
  return source
    .split("\n")
    .map((line) => (line.length > 0 ? "  " + line : line))
    .join("\n");
}
