import { cac } from "cac";
import { performance } from "node:perf_hooks";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { expandEntries, loadConfigFile, resolveConfig } from "./config.js";
import { runBundle, runInspect } from "./bundler.js";
import type {
  BundleMode,
  BundlerConfig,
  BundleStats,
  CircularMode,
  LuaVersion,
  MetadataMode,
} from "./types.js";

const cli = cac("lua-forge");

interface CliFlags {
  entry?: string;
  out?: string;
  config?: string;
  mode?: string;
  paths?: string | string[];
  ignore?: string | string[];
  root?: string;
  lua?: string;
  target?: string;
  requireFn?: string;
  metadata?: string | boolean;
  circular?: string;
  minify?: boolean;
  isolate?: boolean;
  stats?: boolean;
}

function toArray(value: string | string[] | undefined): string[] | undefined {
  if (value === undefined) return undefined;
  return Array.isArray(value) ? value : [value];
}

/** --metadata, --metadata debug, --metadata false */
function parseMetadata(value: string | boolean | undefined): MetadataMode | undefined {
  if (value === undefined) return undefined;
  if (value === true) return true;
  if (value === "debug") return "debug";
  if (value === "false") return false;
  return true;
}

/** Merge config from file + flags (flags win). */
async function buildConfig(flags: CliFlags): Promise<BundlerConfig> {
  const fileConfig: BundlerConfig = flags.config
    ? await loadConfigFile(flags.config)
    : {};

  const merged: BundlerConfig = { ...fileConfig };
  if (flags.entry) merged.entry = flags.entry;
  if (flags.out) merged.output = flags.out;
  if (flags.mode) merged.mode = flags.mode as BundleMode;
  if (flags.root) merged.root = flags.root;
  if (flags.lua) merged.luaVersion = flags.lua as LuaVersion;
  if (flags.target) merged.target = flags.target as BundlerConfig["target"];
  if (flags.requireFn) merged.runtimeRequire = flags.requireFn;
  if (flags.circular) merged.circular = flags.circular as CircularMode;
  const paths = toArray(flags.paths);
  if (paths) merged.paths = paths;
  const ignore = toArray(flags.ignore);
  if (ignore) merged.ignoredModuleNames = ignore;
  const metadata = parseMetadata(flags.metadata);
  if (metadata !== undefined) merged.metadata = metadata;
  if (flags.minify) merged.minify = true;
  if (flags.isolate) merged.isolate = true;
  // if --entry is given on the CLI, override the multi-entry config
  if (flags.entry) merged.entries = undefined;
  return merged;
}

function printStats(stats: BundleStats): void {
  console.log(`  mode:        ${stats.mode}`);
  console.log(`  modules:     ${stats.moduleCount}`);
  console.log(`  ignored:     ${stats.ignoredCount}`);
  console.log(`  cycles:      ${stats.cycleCount}`);
  console.log(`  bytes in:    ${stats.bytesIn}`);
  console.log(`  bytes out:   ${stats.bytesOut}`);
  console.log(`  files read:  ${stats.filesRead}`);
  console.log(`  files parse: ${stats.filesParsed}`);
  console.log(`  resolve:     ${stats.resolveHits} hit / ${stats.resolveMisses} miss`);
  console.log(`  graph:       ${stats.graphMs.toFixed(2)}ms`);
  console.log(`  generate:    ${stats.generateMs.toFixed(2)}ms`);
  console.log(`  total:       ${stats.totalMs.toFixed(2)}ms`);
}

cli
  .command("build", "Bundle multiple Lua files into one")
  .option("--entry <file>", "entry file")
  .option("--out <file>", "output file")
  .option("--config <file>", "config file (.ts/.js/.json)")
  .option("--mode <mode>", "flat | runtime | auto")
  .option("--root <dir>", "root directory for resolution")
  .option("--paths <pattern>", "path pattern (repeatable)")
  .option("--ignore <name>", "ignored module name (repeatable)")
  .option("--lua <version>", "5.4 | 5.3 | LuaJIT")
  .option("--target <target>", "fivem | generic")
  .option("--require-fn <expr>", "Lua expression to require modules that are not bundled")
  .option("--circular <mode>", "error | runtime-fallback")
  .option("--metadata [mode]", "true | false | debug")
  .option("--minify", "minify output")
  .option("--isolate", "isolate global require")
  .option("--stats", "show benchmark/debug stats")
  .action(async (flags: CliFlags) => {
    const base = await buildConfig(flags);
    const entries = expandEntries(base);

    for (const { name, config: entryConfig } of entries) {
      const config = resolveConfig(entryConfig);
      if (!config.entry) {
        console.error(`error: [${name}] entry is required`);
        process.exit(1);
      }
      if (!config.output) {
        console.error(`error: [${name}] output is required`);
        process.exit(1);
      }

      const result = await runBundle(config);
      await mkdir(path.dirname(config.output), { recursive: true });
      await writeFile(config.output, result.code, "utf8");

      const tag = entries.length > 1 ? `[${name}] ` : "";
      console.log(
        `✓ ${tag}${config.output}  (${result.stats.mode}, ${result.stats.moduleCount} modules, ${result.stats.bytesOut} bytes, ${result.stats.totalMs.toFixed(2)}ms)`,
      );
      if (flags.stats) printStats(result.stats);
    }
  });

cli
  .command("inspect", "Show the dependency graph of an entry")
  .option("--entry <file>", "entry file")
  .option("--config <file>", "config file")
  .option("--root <dir>", "root directory")
  .option("--paths <pattern>", "path pattern (repeatable)")
  .option("--ignore <name>", "ignored module name (repeatable)")
  .option("--lua <version>", "5.4 | 5.3 | LuaJIT")
  .option("--json", "output as JSON")
  .action(async (flags: CliFlags & { json?: boolean }) => {
    const config = resolveConfig(await buildConfig(flags));
    if (!config.entry) {
      console.error("error: --entry is required");
      process.exit(1);
    }
    const graph = await runInspect(config);

    if (flags.json) {
      const json = {
        entry: graph.entry,
        modules: [...graph.modules.values()].map((node) => ({
          path: node.path,
          isRoot: node.isRoot,
          names: [...node.names],
          deps: node.deps.map((dep) => ({ name: dep.name, path: dep.path })),
        })),
        order: graph.order,
        ignored: graph.ignored,
        cycles: graph.cycles,
      };
      console.log(JSON.stringify(json, null, 2));
      return;
    }

    console.log(`entry: ${graph.entry}`);
    console.log(`modules: ${graph.modules.size}`);
    console.log(`\nload order (dependency-first):`);
    graph.order.forEach((modulePath, i) => {
      const node = graph.modules.get(modulePath);
      const tag = node?.isRoot ? " (root)" : "";
      console.log(`  ${i + 1}. ${path.relative(config.root, modulePath)}${tag}`);
    });
    if (graph.ignored.length > 0) {
      console.log(`\nignored: ${graph.ignored.join(", ")}`);
    }
    if (graph.cycles.length > 0) {
      console.log(`\ncircular requires:`);
      for (const cycle of graph.cycles) {
        console.log(`  ${cycle.map((p) => path.relative(config.root, p)).join(" -> ")}`);
      }
    }
  });

function countOccurrences(text: string, needle: string): number {
  let count = 0;
  let index = text.indexOf(needle);
  while (index !== -1) {
    count++;
    index = text.indexOf(needle, index + needle.length);
  }
  return count;
}

cli
  .command("benchmark", "Measure time + compare flat vs runtime mode")
  .option("--entry <file>", "entry file")
  .option("--config <file>", "config file")
  .option("--root <dir>", "root directory")
  .option("--paths <pattern>", "path pattern (repeatable)")
  .option("--ignore <name>", "ignored module name (repeatable)")
  .option("--lua <version>", "5.4 | 5.3 | LuaJIT")
  .option("--runs <n>", "number of runs", { default: 20 })
  .action(async (flags: CliFlags & { runs?: number }) => {
    const base = await buildConfig(flags);
    const runs = Number(flags.runs) || 20;

    for (const mode of ["flat", "runtime"] as BundleMode[]) {
      const config = resolveConfig({ ...base, mode, entries: undefined });
      if (!config.entry) {
        console.error("error: --entry is required");
        process.exit(1);
      }

      const times: number[] = [];
      let bytesOut = 0;
      let modules = 0;
      let loaderRefs = 0;
      let requireRefs = 0;
      let failed = "";

      for (let i = 0; i < runs; i++) {
        const start = performance.now();
        try {
          const result = await runBundle(config);
          bytesOut = result.stats.bytesOut;
          modules = result.stats.moduleCount;
          loaderRefs = countOccurrences(result.code, "__bundle_require(");
          requireRefs = countOccurrences(result.code, "__lf_require(");
        } catch (error) {
          failed = (error as Error).message.split("\n")[0];
          break;
        }
        times.push(performance.now() - start);
      }

      if (failed) {
        console.log(`${mode.padEnd(8)} skipped (${failed})`);
        continue;
      }
      times.sort((a, b) => a - b);
      const avg = times.reduce((sum, value) => sum + value, 0) / times.length;
      console.log(
        `${mode.padEnd(8)} avg ${avg.toFixed(2)}ms  min ${times[0].toFixed(2)}ms  median ${times[Math.floor(times.length / 2)].toFixed(2)}ms` +
          `  | ${modules} modules, ${bytesOut} bytes, loaderRefs ${loaderRefs}, fallbackRefs ${requireRefs}  (x${runs})`,
      );
    }
  });

cli.help();
cli.version("0.1.0");
cli.parse();
