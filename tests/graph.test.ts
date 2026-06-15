import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { inspect } from "../src/index.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, "fixtures");

describe("dependency graph", () => {
  it("รวม dependency แบบ recursive ครบ", async () => {
    const graph = await inspect({
      entry: path.join(fixtures, "client", "main.lua"),
      root: fixtures,
      ignoredModuleNames: ["json"],
    });
    const names = [...graph.modules.values()].map((node) =>
      path.basename(node.path),
    );
    expect(names).toContain("main.lua");
    expect(names).toContain("utils.lua");
    expect(names).toContain("config.lua");
    expect(names).toContain("format.lua");
  });

  it("dedupe ไฟล์เดียวกันไม่ซ้ำ", async () => {
    const source = `require("modules.format")\nrequire("modules.format")`;
    const graph = await inspect({
      entry: path.join(fixtures, "client", "main.lua"),
      root: fixtures,
      ignoredModuleNames: ["json"],
    });
    const formatNodes = [...graph.modules.values()].filter(
      (node) => path.basename(node.path) === "format.lua",
    );
    expect(formatNodes).toHaveLength(1);
    void source;
  });

  it("บันทึก ignored module", async () => {
    const graph = await inspect({
      entry: path.join(fixtures, "client", "main.lua"),
      root: fixtures,
      ignoredModuleNames: ["json"],
    });
    expect(graph.ignored).toContain("json");
  });

  it("load order = dependency-first (root ท้ายสุด)", async () => {
    const graph = await inspect({
      entry: path.join(fixtures, "client", "main.lua"),
      root: fixtures,
      ignoredModuleNames: ["json"],
    });
    const last = graph.order[graph.order.length - 1];
    expect(graph.modules.get(last)?.isRoot).toBe(true);
    // format ต้องมาก่อน utils (utils require format)
    const order = graph.order.map((p) => path.basename(p));
    expect(order.indexOf("format.lua")).toBeLessThan(order.indexOf("utils.lua"));
  });

  it("ตรวจ circular require", async () => {
    const graph = await inspect({
      entry: path.join(fixtures, "circular", "a.lua"),
      root: fixtures,
    });
    expect(graph.cycles.length).toBeGreaterThan(0);
  });
});
