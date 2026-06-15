import path from "node:path";
import type { BuildCache } from "./cache.js";
import type { ResolvedConfig } from "./types.js";

/** Error raised when a module cannot be resolved — carries full report data. */
export interface ModuleResolveError extends Error {
  name: "ModuleResolveError";
  moduleName: string;
  importer: string | null;
  loc: { line: number; column: number } | null;
  searched: string[];
}

function createResolveError(
  moduleName: string,
  importer: string | null,
  loc: { line: number; column: number } | null,
  searched: string[],
): ModuleResolveError {
  const where = importer
    ? `${importer}${loc ? `:${loc.line}:${loc.column}` : ""}`
    : "<entry>";
  const error = new Error(
    `cannot resolve module: "${moduleName}"\n` +
      `  importer: ${where}\n` +
      `  searched:\n${searched.map((p) => `    - ${p}`).join("\n")}`,
  ) as ModuleResolveError;
  error.name = "ModuleResolveError";
  error.moduleName = moduleName;
  error.importer = importer;
  error.loc = loc;
  error.searched = searched;
  return error;
}

export function isModuleResolveError(error: unknown): error is ModuleResolveError {
  return error instanceof Error && error.name === "ModuleResolveError";
}

/** Convert a module name ("a.b.c") to a relative path ("a/b/c"). */
function nameToPath(name: string): string {
  return name.replace(/\./g, "/");
}

/** Build candidate paths from the patterns. */
function buildCandidates(
  moduleName: string,
  config: ResolvedConfig,
  importerPath: string | null,
): string[] {
  const asPath = nameToPath(moduleName);
  const roots: string[] = [config.root];
  // also try relative to the requiring file's directory (convenience)
  if (importerPath) roots.unshift(path.dirname(importerPath));

  const candidates: string[] = [];
  const seen = new Set<string>();
  for (const root of roots) {
    for (const pattern of config.paths) {
      const rel = pattern.replace(/\?/g, asPath);
      const full = path.resolve(root, rel);
      if (!seen.has(full)) {
        seen.add(full);
        candidates.push(full);
      }
    }
  }
  return candidates;
}

export interface ResolveResult {
  /** Absolute path if resolved. */
  path: string | null;
  /** Whether this module is in the ignored list. */
  ignored: boolean;
}

/**
 * Resolve a module name -> absolute file path.
 * - uses resolveHook first if present
 * - checks the ignored list
 * - caches the result by importer+name
 */
export async function resolveModule(
  moduleName: string,
  importerPath: string | null,
  config: ResolvedConfig,
  cache: BuildCache,
  loc: { line: number; column: number } | null = null,
): Promise<ResolveResult> {
  if (config.ignoredModuleNames.has(moduleName)) {
    return { path: null, ignored: true };
  }

  const cacheKey = `${importerPath ?? ""}::${moduleName}`;
  const cached = cache.getResolved(cacheKey);
  if (cached !== undefined) {
    return { path: cached, ignored: false };
  }

  if (config.resolveHook) {
    const hooked = await config.resolveHook(moduleName, importerPath);
    if (hooked) {
      const abs = path.resolve(hooked);
      cache.setResolved(cacheKey, abs);
      return { path: abs, ignored: false };
    }
  }

  const candidates = buildCandidates(moduleName, config, importerPath);
  for (const candidate of candidates) {
    if (await cache.exists(candidate)) {
      cache.setResolved(cacheKey, candidate);
      return { path: candidate, ignored: false };
    }
  }

  throw createResolveError(moduleName, importerPath, loc, candidates);
}
