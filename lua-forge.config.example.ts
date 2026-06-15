import { defineConfig } from "lua-forge";

export default defineConfig({
  target: "fivem",
  // "auto" = flat when there is no circular require, otherwise follow the circular policy
  mode: "auto",
  // false = production (no path leak), true / "debug" = add relative path comments
  metadata: false,
  // on a circular require in flat: "error" or "runtime-fallback"
  circular: "error",

  paths: ["?", "?.lua", "modules/?.lua", "src/?.lua", "src/?/init.lua"],
  ignoredModuleNames: [],

  // multi-entry: build client + server with a single command (lua-forge build --config ...)
  entries: {
    client: {
      entry: "src/client/main.lua",
      output: "build/client.lua",
    },
    server: {
      entry: "src/server/main.lua",
      output: "build/server.lua",
    },
  },

  // modules that are not bundled are required via this expression (FiveM has no global require)
  // runtimeRequire: "_G.myloader",

  // resolveHook: (name, importer) => null,
  // dynamicRequireHook: (dyn, importer) => null,
  // persistentCache: ".lua-forge-cache.json",
});
