import type { BuildCache } from "./cache.js";
import { parseRequires } from "./parser.js";
import { resolveModule } from "./resolver.js";
import type {
  BundleGraph,
  ModuleNode,
  ResolvedConfig,
  ResolvedDep,
} from "./types.js";

interface BuildGraphInput {
  /** path of the root module */
  rootPath: string;
  config: ResolvedConfig;
  cache: BuildCache;
}

/** Read + parse a file into a ModuleNode (deps not resolved yet). */
async function loadModule(
  path: string,
  isRoot: boolean,
  config: ResolvedConfig,
  cache: BuildCache,
): Promise<ModuleNode> {
  const source = await cache.readFile(path);
  let parsed = await cache.getParse(path);
  if (!parsed) {
    parsed = parseRequires(source, config.luaVersion, path);
    cache.setParse(path, parsed);
  }
  return {
    path,
    names: new Set<string>(),
    source,
    requires: parsed.requires,
    dynamic: parsed.dynamic,
    deps: [],
    isRoot,
  };
}

/**
 * Build the dependency graph recursively from the root.
 * - dedupe by absolute path
 * - resolve deps + record every module name pointing to the same file
 * - detect circular dependencies via DFS coloring
 * - return load order, dependency-first (post-order)
 */
export async function buildGraph(
  input: BuildGraphInput,
): Promise<BundleGraph> {
  const { rootPath, config, cache } = input;
  const modules = new Map<string, ModuleNode>();
  const ignored = new Set<string>();

  // load + resolve deps of every reachable module
  async function ensureModule(
    path: string,
    isRoot: boolean,
  ): Promise<ModuleNode> {
    const existing = modules.get(path);
    if (existing) return existing;

    const node = await loadModule(path, isRoot, config, cache);
    modules.set(path, node);

    // resolve dependencies in parallel
    const resolved = await Promise.all(
      node.requires.map(async (call): Promise<ResolvedDep | null> => {
        const result = await resolveModule(
          call.name,
          path,
          config,
          cache,
          call.loc,
        );
        if (result.ignored) {
          ignored.add(call.name);
          return null;
        }
        return { name: call.name, path: result.path!, call };
      }),
    );

    for (const dep of resolved) {
      if (!dep) continue;
      node.deps.push(dep);
      const child = await ensureModule(dep.path, false);
      child.names.add(dep.name);
    }

    return node;
  }

  const root = await ensureModule(rootPath, true);

  // dynamic require hook — bundle extra modules if the hook returns names
  if (config.dynamicRequireHook) {
    for (const node of [...modules.values()]) {
      for (const dyn of node.dynamic) {
        const extra = await config.dynamicRequireHook(dyn, node.path);
        if (!extra) continue;
        for (const name of extra) {
          const result = await resolveModule(name, node.path, config, cache);
          if (result.ignored || !result.path) {
            ignored.add(name);
            continue;
          }
          const child = await ensureModule(result.path, false);
          child.names.add(name);
          node.deps.push({
            name,
            path: result.path,
            call: { name, loc: dyn.loc, range: dyn.range },
          });
        }
      }
    }
  }

  const { order, cycles } = topoSort(root.path, modules);

  return {
    entry: rootPath,
    modules,
    order,
    ignored: [...ignored],
    cycles,
    rootPath: root.path,
  };
}

/**
 * post-order DFS:
 * - order = dependency-first (root is last)
 * - cycles = list of paths forming a cycle
 */
function topoSort(
  rootPath: string,
  modules: Map<string, ModuleNode>,
): { order: string[]; cycles: string[][] } {
  const order: string[] = [];
  const cycles: string[][] = [];
  // 0 = unvisited, 1 = visiting, 2 = done
  const color = new Map<string, number>();
  const stack: string[] = [];

  function visit(path: string): void {
    const c = color.get(path) ?? 0;
    if (c === 2) return;
    if (c === 1) {
      // back-edge found -> slice the cycle out of the stack
      const start = stack.indexOf(path);
      cycles.push([...stack.slice(start), path]);
      return;
    }

    color.set(path, 1);
    stack.push(path);

    const node = modules.get(path);
    if (node) {
      for (const dep of node.deps) {
        visit(dep.path);
      }
    }

    stack.pop();
    color.set(path, 2);
    order.push(path);
  }

  visit(rootPath);
  return { order, cycles };
}
