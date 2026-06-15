import path from "node:path";
import { performance } from "node:perf_hooks";
import { createCache, type BuildCache } from "./cache.js";
import { buildGraph } from "./graph.js";
import { assertFlatable, generateFlat } from "./output/flat.js";
import { generateRuntime } from "./output/runtime.js";
import type {
  BundleGraph,
  BundleResult,
  BundleStats,
  ResolvedConfig,
} from "./types.js";

/**
 * Decide the actual mode from config.mode + cycles.
 * - "runtime" / "flat" -> as-is (flat + circular -> apply circular policy)
 * - "auto" -> flat when no circular, otherwise apply circular policy
 * circular policy: "runtime-fallback" -> runtime, "error" -> throw clearly
 */
function resolveMode(
  graph: BundleGraph,
  config: ResolvedConfig,
): "runtime" | "flat" {
  if (config.mode === "runtime") return "runtime";

  const hasCycle = graph.cycles.length > 0;
  if (config.mode === "auto") {
    if (!hasCycle) return "flat";
    if (config.circular === "runtime-fallback") return "runtime";
    assertFlatable(graph); // circular === "error" -> throw
  }

  // explicit "flat"
  if (hasCycle) {
    if (config.circular === "runtime-fallback") return "runtime";
    assertFlatable(graph); // throw
  }
  return "flat";
}

function generate(
  graph: BundleGraph,
  config: ResolvedConfig,
  mode: "runtime" | "flat",
): string {
  // pass config with mode = the actual one so the banner shows the right mode
  const resolved: ResolvedConfig = { ...config, mode };
  return mode === "flat"
    ? generateFlat(graph, resolved)
    : generateRuntime(graph, resolved);
}

function collectStats(
  graph: BundleGraph,
  code: string,
  mode: "runtime" | "flat",
  cache: BuildCache,
  timings: { graphMs: number; generateMs: number; totalMs: number },
): BundleStats {
  let bytesIn = 0;
  for (const node of graph.modules.values()) {
    bytesIn += Buffer.byteLength(node.source, "utf8");
  }
  const c = cache.counters;
  return {
    mode,
    moduleCount: graph.modules.size,
    ignoredCount: graph.ignored.length,
    cycleCount: graph.cycles.length,
    bytesIn,
    bytesOut: Buffer.byteLength(code, "utf8"),
    filesRead: c.filesRead,
    filesParsed: c.filesParsed,
    resolveHits: c.resolveHits,
    resolveMisses: c.resolveMisses,
    graphMs: timings.graphMs,
    generateMs: timings.generateMs,
    totalMs: timings.totalMs,
  };
}

async function buildFrom(
  rootPath: string,
  config: ResolvedConfig,
  cache: BuildCache,
): Promise<BundleResult> {
  const start = performance.now();

  const graphStart = performance.now();
  const graph = await buildGraph({ rootPath, config, cache });
  const graphMs = performance.now() - graphStart;

  const mode = resolveMode(graph, config);

  const genStart = performance.now();
  const code = generate(graph, config, mode);
  const generateMs = performance.now() - genStart;

  await cache.flush();
  const totalMs = performance.now() - start;

  return {
    code,
    graph,
    stats: collectStats(graph, code, mode, cache, {
      graphMs,
      generateMs,
      totalMs,
    }),
  };
}

/** Bundle from an entry file. */
export async function runBundle(config: ResolvedConfig): Promise<BundleResult> {
  if (!config.entry) {
    throw new Error("entry is required for bundle()");
  }
  const cache = createCache(config.persistentCache);
  return buildFrom(config.entry, config, cache);
}

/** Bundle directly from a source string (virtual entry). */
export async function runBundleString(
  source: string,
  config: ResolvedConfig,
): Promise<BundleResult> {
  const cache = createCache(false);
  const virtualEntry = path.resolve(config.root, "__entry__.lua");
  cache.seed(virtualEntry, source);
  return buildFrom(virtualEntry, config, cache);
}

/** Build the dependency graph only (no output generation). */
export async function runInspect(
  config: ResolvedConfig,
): Promise<BundleGraph> {
  if (!config.entry) {
    throw new Error("entry is required for inspect()");
  }
  const cache = createCache(config.persistentCache);
  const graph = await buildGraph({
    rootPath: config.entry,
    config,
    cache,
  });
  await cache.flush();
  return graph;
}
