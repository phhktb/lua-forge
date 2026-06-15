import path from "node:path";
import { pathToFileURL } from "node:url";
import type { BundlerConfig, ResolvedConfig } from "./types.js";

const DEFAULT_PATHS = ["?", "?.lua", "modules/?.lua"];

/** Use in a config file for type safety: export default defineConfig({...}). */
export function defineConfig(config: BundlerConfig): BundlerConfig {
  return config;
}

/** Apply defaults to every field. */
export function resolveConfig(config: BundlerConfig): ResolvedConfig {
  const entry = config.entry ? path.resolve(config.entry) : null;
  const root = config.root
    ? path.resolve(config.root)
    : entry
      ? path.dirname(entry)
      : process.cwd();

  return {
    entry,
    output: config.output ? path.resolve(config.output) : null,
    // default = "runtime": safe require-preserving output unless the caller opts into flat/auto
    mode: config.mode ?? "runtime",
    paths: config.paths && config.paths.length > 0 ? config.paths : DEFAULT_PATHS,
    root,
    ignoredModuleNames: new Set(config.ignoredModuleNames ?? []),
    metadata: config.metadata ?? false,
    circular: config.circular ?? "error",
    minify: config.minify ?? false,
    isolate: config.isolate ?? false,
    luaVersion: config.luaVersion ?? "5.4",
    target: config.target ?? "generic",
    runtimeRequire: config.runtimeRequire ?? null,
    resolveHook: config.resolveHook ?? null,
    dynamicRequireHook: config.dynamicRequireHook ?? null,
    persistentCache: config.persistentCache ?? false,
  };
}

/**
 * Expand a multi-entry config into a list of single configs.
 * - has entries -> one config per entry (entry-level fields override)
 * - no entries -> [{ name: "default", config }]
 */
export function expandEntries(
  config: BundlerConfig,
): Array<{ name: string; config: BundlerConfig }> {
  if (!config.entries) {
    return [{ name: "default", config }];
  }
  const { entries, ...shared } = config;
  return Object.entries(entries).map(([name, entry]) => ({
    name,
    config: { ...shared, ...entry },
  }));
}

/** Load config from a .ts / .js / .mjs / .json file. */
export async function loadConfigFile(configPath: string): Promise<BundlerConfig> {
  const abs = path.resolve(configPath);

  if (abs.endsWith(".json")) {
    const { readFile } = await import("node:fs/promises");
    return JSON.parse(await readFile(abs, "utf8")) as BundlerConfig;
  }

  // .js/.mjs work on any Node >= 18; .ts relies on native type-stripping (Node >= 22.18)
  let mod: Record<string, unknown>;
  try {
    mod = await import(pathToFileURL(abs).href);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/\.[mc]?ts$/.test(abs)) {
      throw new Error(
        `failed to load TypeScript config: ${configPath}\n` +
          `  ${message}\n` +
          `  .ts config needs Node >= 22.18 (type stripping). ` +
          `On older Node, use a .js / .mjs / .json config instead.`,
      );
    }
    throw error;
  }
  const config = (mod.default ?? mod) as BundlerConfig;
  if (!config || typeof config !== "object") {
    throw new Error(`config file did not export a config object: ${configPath}`);
  }
  return config;
}
