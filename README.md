# lua-forge

Lua bundler สำหรับ FiveM — รวม Lua หลายไฟล์เป็นไฟล์เดียว เร็ว เบา ดูแลง่าย
เขียนด้วย Node.js + TypeScript (modular, ไม่มี OOP หนัก)

## ทำไม

- เร็วกว่า `luabundle` (async I/O + cache content/stat/resolve/parse)
- output 2 mode: `runtime` (รองรับ circular) และ `flat` (เบาสุด เหมาะ production)
- error ชัด: บอก module name + importer + line/column + searched paths
- ใช้ได้ทั้ง CLI และ API
- ไม่ผูกกับ FiveM logic, ไม่ obfuscate/minify by default

## ติดตั้ง

```bash
npm install lua-forge
```

## CLI

```bash
# build (default mode = auto: flat ถ้าไม่ circular)
lua-forge build --entry client/main.lua --out dist/client.lua

# multi-entry: build client + server พร้อมกันจาก config
lua-forge build --config lua-forge.config.ts

# ดู dependency graph
lua-forge inspect --entry client/main.lua --root .

# benchmark runtime vs flat
lua-forge benchmark --entry client/main.lua --runs 50
```

Flags หลัก: `--entry --out --config --mode flat|runtime|auto --target fivem|generic --metadata [true|false|debug] --circular error|runtime-fallback --root --paths --ignore --lua --require-fn --minify --isolate --stats`
(`--paths` / `--ignore` ใส่ซ้ำได้)

## API

```ts
import { bundle, bundleString, inspect } from "lua-forge";

// bundle จาก entry file (เขียนไฟล์ถ้ามี output)
const code = await bundle({
  entry: "client/main.lua",
  output: "dist/client.lua",
  mode: "flat",
  ignoredModuleNames: ["json"],
});

// bundle จาก source string
const out = await bundleString(`local f = require("util")`, { root: "." });

// dependency graph อย่างเดียว
const graph = await inspect({ entry: "server/main.lua" });
```

## Config

ดู [`lua-forge.config.example.ts`](./lua-forge.config.example.ts)

| field | default | คำอธิบาย |
| --- | --- | --- |
| `entry` | — | entry file |
| `output` | — | output path |
| `mode` | `auto` | `auto` \| `flat` \| `runtime` |
| `circular` | `error` | `error` \| `runtime-fallback` (เมื่อ flat เจอ circular) |
| `entries` | — | multi-entry build (เช่น client/server) |
| `paths` | `["?", "?.lua", "modules/?.lua"]` | package.path-style patterns |
| `root` | dir ของ entry | base dir สำหรับ resolve |
| `ignoredModuleNames` | `[]` | module ที่ปล่อยให้ runtime require เอง |
| `metadata` | `false` | `false` (production) \| `true` \| `"debug"` — ไม่ leak absolute path |
| `minify` | `false` | minify เบา (ลบ comment/บรรทัดว่าง) |
| `isolate` | `false` | ไม่ fallback ไป global require |
| `luaVersion` | `5.4` | `5.4` \| `5.3` \| `LuaJIT` |
| `target` | `fivem` | `fivem` \| `generic` |
| `runtimeRequire` | — | Lua expression สำหรับ require module ที่ไม่ถูก bundle |
| `resolveHook` | — | custom resolve |
| `dynamicRequireHook` | — | จัดการ `require(var)` |
| `persistentCache` | `false` | path เก็บ parse cache จาก content hash |

## Output modes

**auto** (default) — เลือก flat ถ้าไม่มี circular; ถ้ามี circular ทำตาม `circular`
(`error` = หยุดพร้อมบอก cycle, `runtime-fallback` = สลับไป runtime อัตโนมัติ)

**flat** — เรียง module ตาม dependency order, แต่ละ module เป็น local var
ไม่มี runtime loader, เบากว่า, เร็วกว่าตอน resource start
ใช้ไม่ได้ถ้ามี circular require (error หรือ fallback ตาม `circular`)

**runtime** — มี `__bundle_require` + module factory + loaded cache (fast path)
+ localize global (`type`/`tostring`/`error`) รองรับ circular require

## FiveM: ไม่มี global require

FiveM (CfxLua) ไม่มี global `require` — lua-forge เลยสร้าง require runtime ของตัวเอง
(`__bundle_require` ใน runtime mode / inline var ใน flat mode) output จึง **ไม่พึ่ง global `require`**

module ที่ไม่ถูก bundle (อยู่ใน `ignoredModuleNames` หรือ dynamic require):
- `target: "fivem"` (default) → เรียกแล้ว **error ชัดเจน** บอกชื่อ module (ไม่ crash แบบ call nil)
- ถ้ามี loader เอง ตั้ง `runtimeRequire` เช่น `"_G.myloader"` หรือ `"exports.x.require"`
- `target: "generic"` → ใช้ global `require` ปกติ (standard Lua)

## Dev

```bash
npm install
npm test        # vitest
npm run build   # tsup -> dist/
npm run typecheck
```
