import { readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import type { ParseResult } from "./types.js";

/**
 * Build cache — content / stat / resolve / parse caches in one place.
 * Everything is in-memory per build; the persistent parse cache is optional.
 */
export interface BuildCache {
  readFile(path: string): Promise<string>;
  exists(path: string): Promise<boolean>;
  /** Set content directly (for virtual files, e.g. bundleString). */
  seed(path: string, source: string): void;
  getResolved(key: string): string | undefined;
  setResolved(key: string, path: string): void;
  getParse(path: string): Promise<ParseResult | undefined>;
  setParse(path: string, result: ParseResult): void;
  readonly counters: CacheCounters;
  flush(): Promise<void>;
}

export interface CacheCounters {
  filesRead: number;
  filesParsed: number;
  resolveHits: number;
  resolveMisses: number;
}

interface PersistentEntry {
  hash: string;
  result: ParseResult;
}

export function createCache(persistentPath: string | false): BuildCache {
  const contentCache = new Map<string, string>();
  const existsCache = new Map<string, boolean>();
  const resolveCache = new Map<string, string>();
  const parseCache = new Map<string, ParseResult>();
  const contentHash = new Map<string, string>();

  let persistent: Record<string, PersistentEntry> = {};
  let persistentLoaded = false;
  let persistentDirty = false;
  const counters: CacheCounters = {
    filesRead: 0,
    filesParsed: 0,
    resolveHits: 0,
    resolveMisses: 0,
  };

  async function loadPersistent(): Promise<void> {
    if (persistentLoaded || !persistentPath) return;
    persistentLoaded = true;
    try {
      persistent = JSON.parse(await readFile(persistentPath, "utf8"));
    } catch {
      persistent = {};
    }
  }

  async function read(path: string): Promise<string> {
    const cached = contentCache.get(path);
    if (cached !== undefined) {
      return cached;
    }
    const source = await readFile(path, "utf8");
    counters.filesRead++;
    contentCache.set(path, source);
    existsCache.set(path, true);
    contentHash.set(path, createHash("sha1").update(source).digest("hex"));
    return source;
  }

  async function exists(path: string): Promise<boolean> {
    const cached = existsCache.get(path);
    if (cached !== undefined) return cached;
    try {
      const info = await stat(path);
      const ok = info.isFile();
      existsCache.set(path, ok);
      return ok;
    } catch {
      existsCache.set(path, false);
      return false;
    }
  }

  async function getParse(path: string): Promise<ParseResult | undefined> {
    const mem = parseCache.get(path);
    if (mem) {
      return mem;
    }
    if (persistentPath) {
      await loadPersistent();
      const entry = persistent[path];
      if (entry) {
        // read content first so the hash is ready
        await read(path);
        if (entry.hash === contentHash.get(path)) {
          parseCache.set(path, entry.result);
          return entry.result;
        }
      }
    }
    return undefined;
  }

  function setParse(path: string, result: ParseResult): void {
    parseCache.set(path, result);
    counters.filesParsed++;
    if (persistentPath) {
      const hash = contentHash.get(path);
      if (hash) {
        persistent[path] = { hash, result };
        persistentDirty = true;
      }
    }
  }

  async function flush(): Promise<void> {
    if (persistentPath && persistentDirty) {
      await writeFile(persistentPath, JSON.stringify(persistent), "utf8");
      persistentDirty = false;
    }
  }

  function seed(path: string, source: string): void {
    contentCache.set(path, source);
    existsCache.set(path, true);
    contentHash.set(path, createHash("sha1").update(source).digest("hex"));
  }

  return {
    readFile: read,
    exists,
    seed,
    getResolved: (key) => {
      const cached = resolveCache.get(key);
      if (cached !== undefined) counters.resolveHits++;
      else counters.resolveMisses++;
      return cached;
    },
    setResolved: (key, path) => {
      resolveCache.set(key, path);
    },
    getParse,
    setParse,
    counters,
    flush,
  };
}
