import path from "node:path";
import type { BundleGraph, ModuleNode, ResolvedConfig } from "../types.js";

/** relative path จาก root + ใช้ forward slash เสมอ (ไม่ leak machine path / cross-platform) */
export function relativePath(config: ResolvedConfig, absPath: string): string {
  const rel = path.relative(config.root, absPath);
  return rel.split(path.sep).join("/");
}

/**
 * comment ระบุ module — gated ด้วย metadata
 * - metadata=false: "" (production ไม่ leak path)
 * - metadata=true/"debug": relative path เท่านั้น (ไม่มี absolute)
 */
export function moduleComment(
  config: ResolvedConfig,
  absPath: string,
  label: string,
): string {
  if (!config.metadata) return "";
  return `-- ${label}: ${relativePath(config, absPath)}`;
}

/** escape string ให้ใส่ใน Lua string literal ได้ */
export function luaString(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** สร้างชื่อ local variable ที่ปลอดภัยจาก path (สำหรับ flat mode) */
export function makeVarName(
  path: string,
  index: number,
  used: Set<string>,
): string {
  const base = path
    .replace(/^.*[\\/]/, "")
    .replace(/\.lua$/i, "")
    .replace(/[^A-Za-z0-9_]/g, "_");
  let name = `__mod_${base || "m"}_${index}`;
  while (used.has(name)) name = `${name}_`;
  used.add(name);
  return name;
}

/** ชื่อ helper สำหรับ require module ที่ไม่ถูก bundle (ignored/dynamic) */
export const REQUIRE_HELPER = "__lf_require";

export interface RequireHelper {
  /** declaration ที่ต้อง prepend (ว่างได้ถ้าไม่ต้องใช้) */
  decl: string;
  /** สร้าง call expression เช่น __lf_require("json") */
  call(name: string): string;
}

/**
 * ตัดสินใจว่า module ที่ไม่ถูก bundle จะถูก require ยังไง
 * - isolate: error เสมอ (bundle ปิดสนิท)
 * - มี runtimeRequire: ใช้ expression ที่ผู้ใช้กำหนด
 * - target generic: ใช้ global require (standard Lua มี)
 * - target fivem (default): error ชัดเจน เพราะ FiveM ไม่มี global require
 */
export function buildRequireHelper(config: ResolvedConfig): RequireHelper {
  const call = (name: string) => `${REQUIRE_HELPER}(${luaString(name)})`;

  if (!config.isolate && config.runtimeRequire) {
    return { decl: `local ${REQUIRE_HELPER} = ${config.runtimeRequire}`, call };
  }

  if (!config.isolate && config.target === "generic") {
    return { decl: `local ${REQUIRE_HELPER} = require`, call };
  }

  // fivem (default) หรือ isolate -> ไม่พึ่ง global require, error ชัดเจน
  const decl =
    `local function ${REQUIRE_HELPER}(name)\n` +
    `  error("lua-forge: module '" .. name .. "' ไม่ถูก bundle " ..\n` +
    `    "(target=${config.target} ไม่มี global require) — ` +
    `เพิ่ม module เข้า bundle หรือกำหนด config.runtimeRequire", 2)\n` +
    `end`;
  return { decl, call };
}

/** banner metadata (optional) — ไม่มี absolute path ทุกกรณี */
export function metadataBanner(graph: BundleGraph, config: ResolvedConfig): string {
  if (!config.metadata) return "";
  const lines = [
    "-- Bundled by lua-forge",
    `-- mode: ${config.mode}`,
    `-- entry: ${relativePath(config, graph.entry)}`,
    `-- modules: ${graph.modules.size}`,
  ];
  if (graph.ignored.length > 0) {
    lines.push(`-- ignored: ${graph.ignored.join(", ")}`);
  }
  return lines.join("\n") + "\n";
}

/**
 * minify แบบเบามาก — ลบ comment ทั้งบรรทัด + trailing whitespace + บรรทัดว่าง
 * ไม่แตะ string/structure เพื่อไม่ให้ behavior เปลี่ยน
 */
export function lightMinify(code: string): string {
  return code
    .split("\n")
    .map((line) => line.replace(/\s+$/g, ""))
    .filter((line) => line.length > 0 && !/^\s*--(?!\[)/.test(line))
    .join("\n");
}

/**
 * แทนที่ require call ทั้งหมดใน source ด้วย replacement string
 * ใช้ range จาก parser, replace จากท้ายไปหน้าเพื่อรักษา index
 */
export function replaceRequires(
  node: ModuleNode,
  resolve: (name: string) => string | null,
): string {
  const edits = node.requires
    .map((call) => ({ call, replacement: resolve(call.name) }))
    .filter((edit) => edit.replacement !== null)
    .sort((a, b) => b.call.range[0] - a.call.range[0]);

  let source = node.source;
  for (const edit of edits) {
    const [start, end] = edit.call.range;
    source = source.slice(0, start) + edit.replacement + source.slice(end);
  }
  return source;
}
