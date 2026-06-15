import { describe, expect, it } from "vitest";
import { parseRequires } from "../src/parser.js";

describe("parser", () => {
  it("เจอ require แบบมี parens", () => {
    const result = parseRequires(`local x = require("a.b")`);
    expect(result.requires.map((r) => r.name)).toEqual(["a.b"]);
  });

  it("เจอ require แบบ string call ไม่มี parens", () => {
    const result = parseRequires(`local x = require "a.b"`);
    expect(result.requires.map((r) => r.name)).toEqual(["a.b"]);
  });

  it("เก็บ line/column", () => {
    const result = parseRequires(`\nlocal x = require("mod")`);
    expect(result.requires[0].loc.line).toBe(2);
    expect(result.requires[0].loc.column).toBeGreaterThan(0);
  });

  it("เก็บ range ที่ครอบ require call ทั้งก้อน", () => {
    const source = `local x = require("mod")`;
    const [start, end] = parseRequires(source).requires[0].range;
    expect(source.slice(start, end)).toBe(`require("mod")`);
  });

  it("แยก dynamic require (arg ไม่ใช่ literal)", () => {
    const result = parseRequires(`local n = "x"\nlocal m = require(n)`);
    expect(result.requires).toHaveLength(0);
    expect(result.dynamic).toHaveLength(1);
    expect(result.dynamic[0].argText).toBe("n");
  });

  it("เจอหลาย require", () => {
    const result = parseRequires(`require("a")\nrequire("b")\nrequire("c")`);
    expect(result.requires.map((r) => r.name)).toEqual(["a", "b", "c"]);
  });

  it("throw error ที่ชัดเจนเมื่อ syntax พัง", () => {
    expect(() => parseRequires(`local = =`)).toThrow(/parse failed/);
  });
});
