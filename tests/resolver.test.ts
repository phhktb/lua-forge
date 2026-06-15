import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { createCache } from "../src/cache.js";
import { resolveConfig } from "../src/config.js";
import { isModuleResolveError, resolveModule } from "../src/resolver.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, "fixtures");

function makeConfig(extra = {}) {
  return resolveConfig({ root: fixtures, ...extra });
}

describe("resolver", () => {
  it("resolve module name -> path ตาม patterns", async () => {
    const cache = createCache(false);
    const result = await resolveModule("utils", null, makeConfig(), cache);
    expect(result.path).toBe(path.join(fixtures, "utils.lua"));
  });

  it("resolve nested module (dot -> dir)", async () => {
    const cache = createCache(false);
    const result = await resolveModule("shared.config", null, makeConfig(), cache);
    expect(result.path).toBe(path.join(fixtures, "shared", "config.lua"));
  });

  it("resolve ผ่าน modules/?.lua pattern", async () => {
    const cache = createCache(false);
    const result = await resolveModule("format", null, makeConfig(), cache);
    expect(result.path).toBe(path.join(fixtures, "modules", "format.lua"));
  });

  it("ignored module คืน ignored=true ไม่ throw", async () => {
    const cache = createCache(false);
    const config = makeConfig({ ignoredModuleNames: ["json"] });
    const result = await resolveModule("json", null, config, cache);
    expect(result).toEqual({ path: null, ignored: true });
  });

  it("throw error ที่มีข้อมูลครบเมื่อ resolve ไม่ได้", async () => {
    const cache = createCache(false);
    try {
      await resolveModule("nope.missing", "/x/importer.lua", makeConfig(), cache, {
        line: 3,
        column: 5,
      });
      expect.unreachable();
    } catch (error) {
      expect(isModuleResolveError(error)).toBe(true);
      if (isModuleResolveError(error)) {
        expect(error.moduleName).toBe("nope.missing");
        expect(error.importer).toBe("/x/importer.lua");
        expect(error.loc).toEqual({ line: 3, column: 5 });
        expect(error.searched.length).toBeGreaterThan(0);
      }
    }
  });

  it("custom resolveHook ชนะ patterns", async () => {
    const cache = createCache(false);
    const target = path.join(fixtures, "modules", "format.lua");
    const config = makeConfig({ resolveHook: () => target });
    const result = await resolveModule("anything", null, config, cache);
    expect(result.path).toBe(target);
  });
});
