import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { expandEntries, resolveConfig } from "./config.js";
import { runBundle, runBundleString, runInspect } from "./bundler.js";
import type {
  BundleGraph,
  BundleResult,
  BundlerConfig,
} from "./types.js";

export type {
  BundlerConfig,
  ResolvedConfig,
  BundleMode,
  MetadataMode,
  CircularMode,
  LuaVersion,
  BundleTarget,
  EntryConfig,
  BundleGraph,
  BundleResult,
  BundleStats,
  ModuleNode,
  ResolvedDep,
  RequireCall,
  DynamicRequire,
  ResolveHook,
  DynamicRequireHook,
} from "./types.js";

export { defineConfig, resolveConfig, loadConfigFile, expandEntries } from "./config.js";
export { parseRequires } from "./parser.js";
export { isModuleResolveError } from "./resolver.js";

/**
 * bundle จาก entry file -> Lua source string
 * เขียนไฟล์ output ให้ด้วยถ้ามี config.output
 */
export async function bundle(config: BundlerConfig): Promise<string> {
  const result = await bundleWithStats(config);
  return result.code;
}

/** เหมือน bundle() แต่คืน stats + graph ด้วย */
export async function bundleWithStats(
  config: BundlerConfig,
): Promise<BundleResult> {
  const resolved = resolveConfig(config);
  const result = await runBundle(resolved);

  if (resolved.output) {
    await mkdir(path.dirname(resolved.output), { recursive: true });
    await writeFile(resolved.output, result.code, "utf8");
  }
  return result;
}

/** bundle จาก source string ตรง ๆ (ไม่เขียนไฟล์) */
export async function bundleString(
  source: string,
  config: BundlerConfig = {},
): Promise<string> {
  const resolved = resolveConfig(config);
  const result = await runBundleString(source, resolved);
  return result.code;
}

/** สร้าง dependency graph อย่างเดียว */
export async function inspect(config: BundlerConfig): Promise<BundleGraph> {
  const resolved = resolveConfig(config);
  return runInspect(resolved);
}

/**
 * bundle ทุก entry จาก multi-entry config (เช่น client + server)
 * คืน map: ชื่อ entry -> ผลลัพธ์
 */
export async function bundleAll(
  config: BundlerConfig,
): Promise<Record<string, BundleResult>> {
  const results: Record<string, BundleResult> = {};
  for (const { name, config: entryConfig } of expandEntries(config)) {
    results[name] = await bundleWithStats(entryConfig);
  }
  return results;
}
