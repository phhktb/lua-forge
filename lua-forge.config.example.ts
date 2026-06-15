import { defineConfig } from "lua-forge";

export default defineConfig({
  target: "fivem",
  // "auto" = flat ถ้าไม่ circular, ไม่งั้นตาม circular policy
  mode: "auto",
  // false = production (ไม่ leak path), true / "debug" = ใส่ relative path comment
  metadata: false,
  // เจอ circular ใน flat: "error" หรือ "runtime-fallback"
  circular: "error",

  paths: ["?", "?.lua", "modules/?.lua", "src/?.lua", "src/?/init.lua"],
  ignoredModuleNames: [],

  // multi-entry: build client + server ด้วยคำสั่งเดียว (lua-forge build --config ...)
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

  // module ที่ไม่ถูก bundle จะ require ผ่าน expression นี้ (FiveM ไม่มี global require)
  // runtimeRequire: "_G.myloader",

  // resolveHook: (name, importer) => null,
  // dynamicRequireHook: (dyn, importer) => null,
  // persistentCache: ".lua-forge-cache.json",
});
