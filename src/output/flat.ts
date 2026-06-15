import type { BundleGraph, ResolvedConfig } from "../types.js";
import {
  buildRequireHelper,
  lightMinify,
  makeVarName,
  metadataBanner,
  moduleComment,
  replaceRequires,
} from "./shared.js";

/** error เมื่อ flat mode เจอ circular require (จัดการไม่ได้แบบ flat) */
export function assertFlatable(graph: BundleGraph): void {
  if (graph.cycles.length === 0) return;
  const detail = graph.cycles
    .map((cycle) => "    " + cycle.join(" -> "))
    .join("\n");
  throw new Error(
    `flat mode ใช้กับ circular require ไม่ได้ — เจอ ${graph.cycles.length} cycle:\n${detail}\n` +
      `  แก้: ใช้ mode "runtime" หรือ ตัด circular dependency`,
  );
}

/**
 * Flat mode:
 * - เรียง module ตาม dependency order (deps ก่อน)
 * - แต่ละ module = local var = (function() ... end)()
 * - require("dep") ถูกแทนด้วยชื่อ local var ตรง ๆ ไม่มี runtime loader
 * - root code อยู่ท้ายสุด
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

  // map module name -> var (ผ่าน deps ของแต่ละ node)
  const body: string[] = [];

  for (const path of graph.order) {
    const node = graph.modules.get(path);
    if (!node) continue;

    // resolver: module name -> var name (bundled dep) หรือ __lf_require (ignored/dynamic)
    const nameToVar = new Map<string, string>();
    for (const dep of node.deps) {
      const depVar = varByPath.get(dep.path);
      if (depVar) nameToVar.set(dep.name, depVar);
    }
    const transformed = replaceRequires(node, (name) => {
      const depVar = nameToVar.get(name);
      if (depVar) return depVar;
      // require ที่ไม่ถูก bundle (ignored) -> ผ่าน helper, ไม่คง global require ดิบ
      usedRequireHelper = true;
      return requireHelper.call(name);
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

  // คั่น block ด้วยบรรทัดว่างเดียว — อ่าน debug ได้ ไม่มี blank เกิน
  const code = [...head, ...body].join("\n\n") + "\n";
  return config.minify ? lightMinify(code) : code;
}

function indent(source: string): string {
  return source
    .split("\n")
    .map((line) => (line.length > 0 ? "  " + line : line))
    .join("\n");
}
