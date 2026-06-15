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
 * ตัดสิน mode จริงจาก config.mode + cycles
 * - "runtime" / "flat" -> ตามนั้น (flat + circular -> ใช้ circular policy)
 * - "auto" -> flat ถ้าไม่ circular, ไม่งั้นใช้ circular policy
 * circular policy: "runtime-fallback" -> runtime, "error" -> throw ชัดเจน
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
  // ส่ง config ที่ mode = ตัวจริง เพื่อให้ banner แสดง mode ถูก
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

/** bundle จาก entry file */
export async function runBundle(config: ResolvedConfig): Promise<BundleResult> {
  if (!config.entry) {
    throw new Error("ต้องระบุ entry สำหรับ bundle()");
  }
  const cache = createCache(config.persistentCache);
  return buildFrom(config.entry, config, cache);
}

/** bundle จาก source string ตรง ๆ (virtual entry) */
export async function runBundleString(
  source: string,
  config: ResolvedConfig,
): Promise<BundleResult> {
  const cache = createCache(false);
  const virtualEntry = path.resolve(config.root, "__entry__.lua");
  cache.seed(virtualEntry, source);
  return buildFrom(virtualEntry, config, cache);
}

/** สร้าง dependency graph อย่างเดียว (ไม่ generate output) */
export async function runInspect(
  config: ResolvedConfig,
): Promise<BundleGraph> {
  if (!config.entry) {
    throw new Error("ต้องระบุ entry สำหรับ inspect()");
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
