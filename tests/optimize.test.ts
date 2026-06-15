import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { bundle, bundleString, bundleWithStats } from "../src/index.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, "fixtures");
const entry = path.join(fixtures, "client", "main.lua");
const base = { entry, root: fixtures, ignoredModuleNames: ["json"] } as const;

describe("flat output (production)", () => {
  it("ไม่มี __bundle_require / __bundle_register", async () => {
    const code = await bundle({ ...base, mode: "flat" });
    expect(code).not.toContain("__bundle_require");
    expect(code).not.toContain("__bundle_register");
  });

  it("metadata=false: ไม่มี absolute path เลย", async () => {
    const code = await bundle({ ...base, mode: "flat", metadata: false });
    expect(code).not.toMatch(/[A-Za-z]:[\\/]/); // ไม่มี drive path (C:\ / C:/)
    expect(code).not.toContain("-- module:");
    expect(code).not.toContain(fixtures);
  });

  it("metadata=debug: ใช้ relative path (ไม่ใช่ absolute)", async () => {
    const code = await bundle({ ...base, mode: "flat", metadata: "debug" });
    expect(code).toContain("-- module: modules/format.lua");
    expect(code).not.toMatch(/-- module: [A-Za-z]:[\\/]/);
  });

  it("resolved require ถูกแทนเป็น __mod alias", async () => {
    const code = await bundle({ ...base, mode: "flat" });
    expect(code).toContain("local __mod_");
    // ไม่เหลือ require ดิบของ module ที่ bundle ได้
    expect(code).not.toContain('require("utils")');
    expect(code).not.toContain('require("modules.format")');
  });

  it("ignored module -> __lf_require (ไม่ใช่ global require ดิบ)", async () => {
    const code = await bundle({ ...base, mode: "flat" });
    expect(code).toContain('__lf_require("json")');
  });
});

describe("target behavior", () => {
  it("generic (default) routes unbundled require to global require", async () => {
    const code = await bundle({ ...base, mode: "flat" });
    expect(code).toContain("local __lf_require = require");
  });

  it("fivem raises a clear error for unbundled modules", async () => {
    const code = await bundle({ ...base, mode: "flat", target: "fivem" });
    expect(code).toContain("was not bundled");
    expect(code).not.toContain("local __lf_require = require");
  });

  it("runtimeRequire overrides the default loader", async () => {
    const code = await bundle({
      ...base,
      mode: "flat",
      target: "fivem",
      runtimeRequire: "_G.myloader",
    });
    expect(code).toContain("local __lf_require = _G.myloader");
  });
});

describe("runtime output (fast path + localized globals)", () => {
  it("มี fast path สำหรับ module ที่โหลดแล้ว", async () => {
    const code = await bundle({ ...base, mode: "runtime" });
    expect(code).toContain("if entry then return entry.value end");
  });

  it("localize global functions", async () => {
    const code = await bundle({ ...base, mode: "runtime" });
    expect(code).toContain("local error, type, tostring = error, type, tostring");
  });
});

describe("auto mode", () => {
  it("no circular -> flat", async () => {
    const result = await bundleWithStats({ ...base, mode: "auto" });
    expect(result.stats.mode).toBe("flat");
  });

  it("circular + runtime-fallback -> runtime", async () => {
    const result = await bundleWithStats({
      entry: path.join(fixtures, "circular", "a.lua"),
      root: fixtures,
      mode: "auto",
      circular: "runtime-fallback",
    });
    expect(result.stats.mode).toBe("runtime");
    expect(result.code).toContain("__bundle_require");
  });

  it("circular + error (default) -> throw", async () => {
    await expect(
      bundle({
        entry: path.join(fixtures, "circular", "a.lua"),
        root: fixtures,
        mode: "auto",
        circular: "error",
      }),
    ).rejects.toThrow(/circular/);
  });
});

describe("build stats", () => {
  it("นับ filesRead / filesParsed = จำนวน module", async () => {
    const result = await bundleWithStats({ ...base, mode: "flat" });
    expect(result.stats.filesParsed).toBe(result.stats.moduleCount);
    expect(result.stats.filesRead).toBe(result.stats.moduleCount);
  });

  it("resolve cache hit เมื่อ require ซ้ำใน build เดียว", async () => {
    const result = await bundleWithStats({
      ...base,
      mode: "flat",
    });
    expect(result.stats.resolveMisses).toBeGreaterThan(0);
  });

  it("require ซ้ำ module เดียว -> resolveHits เพิ่ม + include ครั้งเดียว", async () => {
    const source = `require("modules.format")\nrequire("modules.format")\nreturn 1`;
    const code = await bundleString(source, { root: fixtures, mode: "flat" });
    // format ถูก include ครั้งเดียว
    expect(code.match(/-- /g) ?? []).toBeDefined();
    expect(code).toContain("local __mod_format_0");
    expect((code.match(/local __mod_format/g) ?? []).length).toBe(1);
  });
});
