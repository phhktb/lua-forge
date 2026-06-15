import luaparse from "luaparse";
import type {
  DynamicRequire,
  LuaVersion,
  ParseResult,
  RequireCall,
} from "./types.js";

/** Map our luaVersion to a value luaparse supports. */
function toParserVersion(version: LuaVersion): "5.1" | "5.2" | "5.3" | "LuaJIT" {
  if (version === "LuaJIT") return "LuaJIT";
  // luaparse does not support 5.4 yet — use the 5.3 grammar, a sufficient superset for require detection
  if (version === "5.4") return "5.3";
  return "5.3";
}

interface LuaNode {
  type: string;
  // luaparse node fields (loose typing — walked by key)
  [key: string]: unknown;
}

function getLoc(node: LuaNode): { line: number; column: number } {
  const loc = node.loc as
    | { start: { line: number; column: number } }
    | undefined;
  if (loc) return { line: loc.start.line, column: loc.start.column };
  return { line: 0, column: 0 };
}

function getRange(node: LuaNode): [number, number] {
  const range = node.range as [number, number] | undefined;
  return range ?? [0, 0];
}

/** Extract the string value from a StringLiteral node. */
function stringValue(node: LuaNode): string | null {
  if (node.type !== "StringLiteral") return null;
  if (typeof node.value === "string") return node.value;
  // some luaparse builds only keep raw -> strip quotes
  if (typeof node.raw === "string") {
    return node.raw.slice(1, -1);
  }
  return null;
}

/** Check whether base is an identifier named require. */
function isRequireBase(base: LuaNode | undefined): boolean {
  return !!base && base.type === "Identifier" && base.name === "require";
}

/**
 * Parse Lua source and return the list of require calls + dynamic requires.
 * Does not modify the source — only reads positions.
 */
export function parseRequires(
  source: string,
  luaVersion: LuaVersion = "5.4",
  filePath = "<string>",
): ParseResult {
  let ast: LuaNode;
  try {
    ast = luaparse.parse(source, {
      locations: true,
      ranges: true,
      luaVersion: toParserVersion(luaVersion),
      comments: false,
    }) as unknown as LuaNode;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`parse failed: ${filePath}\n  ${message}`);
  }

  const requires: RequireCall[] = [];
  const dynamic: DynamicRequire[] = [];

  function handleRequire(callNode: LuaNode, arg: LuaNode | undefined): void {
    if (!arg) return;
    const name = stringValue(arg);
    if (name !== null) {
      requires.push({
        name,
        loc: getLoc(callNode),
        range: getRange(callNode),
      });
      return;
    }
    const [start, end] = getRange(arg);
    dynamic.push({
      loc: getLoc(callNode),
      range: getRange(callNode),
      argText: source.slice(start, end),
    });
  }

  function walk(node: LuaNode | null | undefined): void {
    if (!node || typeof node !== "object") return;

    if (node.type === "CallExpression" && isRequireBase(node.base as LuaNode)) {
      const args = node.arguments as LuaNode[] | undefined;
      handleRequire(node, args?.[0]);
    } else if (
      node.type === "StringCallExpression" &&
      isRequireBase(node.base as LuaNode)
    ) {
      handleRequire(node, node.argument as LuaNode);
    }

    // walk every child node
    for (const key in node) {
      if (key === "loc" || key === "range" || key === "type") continue;
      const value = node[key];
      if (Array.isArray(value)) {
        for (const item of value) walk(item as LuaNode);
      } else if (value && typeof value === "object") {
        walk(value as LuaNode);
      }
    }
  }

  walk(ast);
  return { requires, dynamic };
}
