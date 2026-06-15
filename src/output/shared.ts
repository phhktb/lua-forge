import path from "node:path";
import type { BundleGraph, ModuleNode, ResolvedConfig } from "../types.js";

/** Relative path from root, always forward-slashed (no machine path leak / cross-platform). */
export function relativePath(config: ResolvedConfig, absPath: string): string {
  const rel = path.relative(config.root, absPath);
  return rel.split(path.sep).join("/");
}

/**
 * Module-identifying comment — gated by metadata.
 * - metadata=false: "" (production, no path leak)
 * - metadata=true/"debug": relative path only (never absolute)
 */
export function moduleComment(
  config: ResolvedConfig,
  absPath: string,
  label: string,
): string {
  if (!config.metadata) return "";
  return `-- ${label}: ${relativePath(config, absPath)}`;
}

/** Escape a string so it can be placed in a Lua string literal. */
export function luaString(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** Build a safe local variable name from a path (for flat mode). */
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

/** Helper name for requiring modules that are not bundled (ignored/dynamic). */
export const REQUIRE_HELPER = "__lf_require";

export interface RequireHelper {
  /** Declaration to prepend (may be empty if unused). */
  decl: string;
  /** Build a call expression, e.g. __lf_require("json"). */
  call(name: string): string;
}

/**
 * Decide how modules that are not bundled get required.
 * - isolate: always error (fully closed bundle)
 * - runtimeRequire set: use the user-provided expression
 * - target generic: use the global require (standard Lua has it)
 * - target fivem (default): clear error, since FiveM has no global require
 */
export function buildRequireHelper(config: ResolvedConfig): RequireHelper {
  const call = (name: string) => `${REQUIRE_HELPER}(${luaString(name)})`;

  if (!config.isolate && config.runtimeRequire) {
    return { decl: `local ${REQUIRE_HELPER} = ${config.runtimeRequire}`, call };
  }

  if (!config.isolate && config.target === "generic") {
    return { decl: `local ${REQUIRE_HELPER} = require`, call };
  }

  // fivem (default) or isolate -> do not rely on a global require, error clearly
  const decl =
    `local function ${REQUIRE_HELPER}(name)\n` +
    `  error("lua-forge: module '" .. name .. "' was not bundled " ..\n` +
    `    "(target=${config.target} has no global require) - ` +
    `add the module to the bundle or set config.runtimeRequire", 2)\n` +
    `end`;
  return { decl, call };
}

/** Metadata banner (optional) — never contains an absolute path. */
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
 * Very light minify — strip full-line comments + trailing whitespace + blank lines.
 * Does not touch strings/structure so behavior never changes.
 */
export function lightMinify(code: string): string {
  return code
    .split("\n")
    .map((line) => line.replace(/\s+$/g, ""))
    .filter((line) => line.length > 0 && !/^\s*--(?!\[)/.test(line))
    .join("\n");
}

/**
 * Replace all require calls in the source with a replacement string.
 * Uses parser ranges, replacing back-to-front to keep indices valid.
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
