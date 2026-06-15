import { defineConfig } from "lua-forge";

export default defineConfig({
  // "generic" = standard Lua (has a global require)
  // "fivem" (or any host without a global require) = self-contained output
  target: "generic",
  // safe default: runtime preserves require semantics
  mode: "runtime",
  // false = production (no path leak), true / "debug" = add relative path comments
  metadata: false,
  // when mode = "auto" or "flat", circular can "error" or "runtime-fallback"
  circular: "error",

  paths: ["?", "?.lua", "modules/?.lua", "src/?.lua", "src/?/init.lua"],
  ignoredModuleNames: [],

  // single entry
  entry: "src/main.lua",
  output: "build/app.lua",

  // or multi-entry: build several outputs with one command (lua-forge build --config ...)
  // entries: {
  //   client: { entry: "src/client/main.lua", output: "build/client.lua" },
  //   server: { entry: "src/server/main.lua", output: "build/server.lua" },
  // },

  // modules that are not bundled are required via this expression
  // (needed for hosts without a global require)
  // runtimeRequire: "_G.myloader",

  // resolveHook: (name, importer) => null,
  // dynamicRequireHook: (dyn, importer) => null,
  // persistentCache: ".lua-forge-cache.json",
});
