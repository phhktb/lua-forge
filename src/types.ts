/**
 * Public types for lua-forge.
 * All plain data + function types — no classes.
 */

export type BundleMode = "runtime" | "flat" | "auto";

export type LuaVersion = "5.4" | "5.3" | "LuaJIT";

export type BundleTarget = "fivem" | "generic";

/**
 * Metadata level in the output:
 * - false: production — no path comments at all (no machine path leak, smallest)
 * - true: banner + relative path comments
 * - "debug": full banner + complete relative path comments
 */
export type MetadataMode = boolean | "debug";

/** What to do when flat mode hits a circular require. */
export type CircularMode = "error" | "runtime-fallback";

/** Location of a require call in the source, for clear errors. */
export interface SourceLocation {
  line: number;
  column: number;
}

/** A require call found by the parser. */
export interface RequireCall {
  /** Module name as written in require("..."). */
  name: string;
  loc: SourceLocation;
  /** Index range [start, end] in the source, for flat-mode replacement. */
  range: [number, number];
}

/** A require whose argument is not a string literal (dynamic). */
export interface DynamicRequire {
  loc: SourceLocation;
  range: [number, number];
  /** Raw text of the argument. */
  argText: string;
}

/** Parse result for a single file. */
export interface ParseResult {
  requires: RequireCall[];
  dynamic: DynamicRequire[];
}

/** Hook to override module name -> path resolution. */
export type ResolveHook = (
  moduleName: string,
  importerPath: string | null,
) => string | null | Promise<string | null>;

/** Hook to handle a dynamic require (returns extra module names to bundle). */
export type DynamicRequireHook = (
  dynamic: DynamicRequire,
  importerPath: string,
) => string[] | null | Promise<string[] | null>;

/** A single entry in a multi-entry config. */
export interface EntryConfig {
  entry: string;
  output?: string;
  mode?: BundleMode;
}

/** User-supplied config (every field optional except entry for bundle()). */
export interface BundlerConfig {
  entry?: string;
  output?: string;
  mode?: BundleMode;
  /** Multi-entry: build several bundles from a single config (e.g. client/server). */
  entries?: Record<string, EntryConfig>;
  /** package.path-style patterns, e.g. "?", "?.lua", "modules/?.lua". */
  paths?: string[];
  /** Root directory for path resolution (default: dirname(entry) or cwd). */
  root?: string;
  /** Module names that are not bundled — left for the runtime to require itself. */
  ignoredModuleNames?: string[];
  /** Metadata comments in the output (false=production, true, "debug"). */
  metadata?: MetadataMode;
  /** What to do when flat mode hits a circular require (default = "error"). */
  circular?: CircularMode;
  minify?: boolean;
  /** Isolate the global require inside the bundle (runtime mode). */
  isolate?: boolean;
  luaVersion?: LuaVersion;
  target?: BundleTarget;
  /**
   * Lua expression used to require modules that are not bundled (ignored/dynamic).
   * - target "generic" (default): uses the global "require" (standard Lua has it)
   * - target "fivem": no global require -> clear error unless this is set
   * e.g. set to "exports.myloader.require" or "_G.require" if you have a custom loader.
   */
  runtimeRequire?: string;
  resolveHook?: ResolveHook;
  dynamicRequireHook?: DynamicRequireHook;
  /** Persistent parse cache keyed by content hash (stored in this file). */
  persistentCache?: string | false;
}

/** Config after all defaults are applied. */
export interface ResolvedConfig {
  entry: string | null;
  output: string | null;
  mode: BundleMode;
  paths: string[];
  root: string;
  ignoredModuleNames: Set<string>;
  metadata: MetadataMode;
  circular: CircularMode;
  minify: boolean;
  isolate: boolean;
  luaVersion: LuaVersion;
  target: BundleTarget;
  runtimeRequire: string | null;
  resolveHook: ResolveHook | null;
  dynamicRequireHook: DynamicRequireHook | null;
  persistentCache: string | false;
}

/** A node in the dependency graph. */
export interface ModuleNode {
  /** Absolute path of the file. */
  path: string;
  /** All module names that resolve to this file (for runtime registration). */
  names: Set<string>;
  source: string;
  requires: RequireCall[];
  dynamic: DynamicRequire[];
  /** Resolved dependencies (excluding ignored). */
  deps: ResolvedDep[];
  isRoot: boolean;
}

export interface ResolvedDep {
  /** Module name as required. */
  name: string;
  /** Target path. */
  path: string;
  /** Originating require call. */
  call: RequireCall;
}

/** inspect result: the full dependency graph. */
export interface BundleGraph {
  entry: string;
  /** Keyed by absolute path. */
  modules: Map<string, ModuleNode>;
  /** Load order (dependency-first), by path. */
  order: string[];
  /** Module names that were ignored. */
  ignored: string[];
  /** Circular cycles found (each cycle is a list of paths). */
  cycles: string[][];
  rootPath: string;
}

export interface BundleStats {
  /** The mode actually used (after resolving "auto"). */
  mode: "runtime" | "flat";
  moduleCount: number;
  ignoredCount: number;
  cycleCount: number;
  bytesIn: number;
  bytesOut: number;
  /** Number of files actually read from disk (excluding cache hits). */
  filesRead: number;
  /** Number of files actually parsed (excluding cache hits). */
  filesParsed: number;
  resolveHits: number;
  resolveMisses: number;
  graphMs: number;
  generateMs: number;
  totalMs: number;
}

export interface BundleResult {
  code: string;
  graph: BundleGraph;
  stats: BundleStats;
}
