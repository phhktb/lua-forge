import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { bundle, bundleString } from "../src/index.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, "fixtures");
const entry = path.join(fixtures, "client", "main.lua");

describe("bundle runtime mode", () => {
  it("default mode uses runtime output", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      ignoredModuleNames: ["json"],
    });
    expect(code).toContain("local function __bundle_require(name)");
    expect(code).toContain('__bundle_require("__lua_forge_root__")');
  });

  it("สร้าง output ที่มี runtime loader + register module", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      mode: "runtime",
      ignoredModuleNames: ["json"],
    });
    expect(code).toContain("local function __bundle_require(name)");
    expect(code).toContain("__modules[");
    expect(code).toContain('__bundle_require("__lua_forge_root__")');
    // ignored module ไม่ถูก register
    expect(code).not.toContain('__modules["json"]');
  });

  it("snapshot runtime output", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      mode: "runtime",
      ignoredModuleNames: ["json"],
    });
    expect(code).toMatchSnapshot();
  });

  it("รองรับ circular ใน runtime mode (ไม่ throw)", async () => {
    const code = await bundle({
      entry: path.join(fixtures, "circular", "a.lua"),
      root: fixtures,
      mode: "runtime",
    });
    expect(code).toContain("__bundle_require");
  });
});

describe("bundle flat mode", () => {
  it("สร้าง output แบบ flat ไม่มี runtime loader", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      mode: "flat",
      ignoredModuleNames: ["json"],
    });
    expect(code).not.toContain("__bundle_require");
    expect(code).toContain("local __mod_");
    expect(code).toContain("(function()");
  });

  it("snapshot flat output", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      mode: "flat",
      ignoredModuleNames: ["json"],
    });
    expect(code).toMatchSnapshot();
  });

  it("throw เมื่อเจอ circular ใน flat mode", async () => {
    await expect(
      bundle({
        entry: path.join(fixtures, "circular", "a.lua"),
        root: fixtures,
        mode: "flat",
      }),
    ).rejects.toThrow(/circular/);
  });
});

describe("bundleString", () => {
  it("bundle จาก source string ตรง ๆ", async () => {
    const code = await bundleString(`local f = require("modules.format")\nreturn f.bold("x")`, {
      root: fixtures,
      mode: "runtime",
    });
    expect(code).toContain("__modules[");
    expect(code).toContain("format");
  });
});

describe("metadata", () => {
  it("ใส่ banner เมื่อ metadata=true", async () => {
    const code = await bundle({
      entry,
      root: fixtures,
      mode: "runtime",
      metadata: true,
      ignoredModuleNames: ["json"],
    });
    expect(code).toContain("-- Bundled by lua-forge");
  });
});
