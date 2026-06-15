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
 * - register แต่ละ module เป็น factory function
 * - __bundle_require: fast path สำหรับ module ที่โหลดแล้ว
 * - localize global ที่ใช้บ่อย (type/tostring/error) ลด global lookup
 * - รองรับ circular require: ตั้ง entry ก่อน run factory (return partial เหมือน Lua ปกติ)
 * - ignored / dynamic require -> __lf_require (FiveM: error ชัด, ไม่พึ่ง global require)
 */
export function generateRuntime(
  graph: BundleGraph,
  config: ResolvedConfig,
): string {
  const head: string[] = [];
  const banner = metadataBanner(graph, config);
  if (banner) head.push(banner.trimEnd());

  const requireHelper = buildRequireHelper(config);

  // loader runtime — boilerplate น้อย, fast path ก่อน
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
  // register modules ตาม load order (dependency-first); root จะ register เป็น key พิเศษ
  for (const path of graph.order) {
    const node = graph.modules.get(path);
    if (!node) continue;

    // root ต้องลงทะเบียนใต้ ROOT_KEY และชื่อจริงของมันด้วย
    // (กรณี circular ที่ module อื่น require root กลับมา)
    const names = node.isRoot ? [ROOT_KEY, ...node.names] : [...node.names];
    if (names.length === 0) continue;

    const comment = moduleComment(config, path, node.isRoot ? "root" : "module");
    const lines: string[] = [];
    if (comment) lines.push(comment);
    lines.push(`__modules[${luaString(names[0])}] = function(require)`);
    lines.push(indent(node.source.trim()));
    lines.push(`end`);
    // ตัว factory เดียว แชร์ให้ทุกชื่อที่ชี้ไฟล์เดียวกัน
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
