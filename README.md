# lua-forge

A Lua bundler for FiveM — combine many Lua files into one. Fast, lightweight, easy to maintain.

## Why

- Fast builds (content/stat/resolve/parse caching)
- Two output modes: `runtime` (handles circular requires) and `flat` (smallest, production-ready)
- Clear errors: module name + importer + line/column + searched paths
- Usable from both the CLI and the API
- No coupling to FiveM logic; no obfuscation/minification by default

## Install

```bash
npm install lua-forge
```

## Writing Lua modules

Author your code as plain Lua files. A module returns a value (usually a table);
other files pull it in with `require("module.name")`. Dots map to folders,
exactly like Lua's `package.path` (`require("modules.format")` -> `modules/format.lua`).

```
src/client/
├── main.lua                 -- entry
├── utils.lua
├── shared/config.lua
└── modules/format.lua
```

```lua
-- src/client/modules/format.lua
local format = {}

function format.bold(text)
  return "**" .. text .. "**"
end

return format            -- the module's return value
```

```lua
-- src/client/utils.lua
local format = require("modules.format")   -- resolved & inlined by the bundler

local utils = {}

function utils.greet(name)
  return format.bold("hello " .. name)
end

return utils
```

```lua
-- src/client/main.lua (entry — no return needed)
local utils  = require("utils")
local config = require("shared.config")

print(utils.greet(config.name))
```

Build it into a single file:

```bash
lua-forge build --entry src/client/main.lua --out build/client.lua --root src/client
```

In the generated bundle, every `require("...")` that the bundler resolved is
replaced — there is no runtime `require` left for those. FiveM-provided globals
(`exports`, `Citizen`, `RegisterNetEvent`, `Config`, ...) are left untouched
because they are not `require` calls.

Then point your resource at the single bundled file:

```lua
-- fxmanifest.lua
fx_version 'cerulean'
game 'gta5'

client_scripts { 'build/client.lua' }
server_scripts { 'build/server.lua' }
```

### Modules not bundled (ignored / dynamic)

FiveM has no global `require`, so a module that is **not** bundled cannot be
required at runtime by default. List such names in `ignoredModuleNames` and
provide a loader via `runtimeRequire`:

```lua
-- somewhere loaded before the bundle (e.g. a shared_script)
_G.myloader = function(name)
  if name == "json" then return require_or_export_your_json() end
end
```

```bash
lua-forge build --entry src/server/main.lua --out build/server.lua \
  --root src/server --ignore json --require-fn "_G.myloader"
```

Inside the bundle the ignored `require("json")` becomes `__lf_require("json")`,
which routes to your `runtimeRequire` expression. Without a loader (default
`target: "fivem"`) it raises a clear error naming the missing module instead of
crashing on a nil call.

## CLI

```bash
# build (default mode = auto: flat when there is no circular require)
lua-forge build --entry client/main.lua --out dist/client.lua

# multi-entry: build client + server together from a config
lua-forge build --config lua-forge.config.ts

# inspect the dependency graph
lua-forge inspect --entry client/main.lua --root .

# benchmark runtime vs flat
lua-forge benchmark --entry client/main.lua --runs 50
```

Main flags: `--entry --out --config --mode flat|runtime|auto --target fivem|generic --metadata [true|false|debug] --circular error|runtime-fallback --root --paths --ignore --lua --require-fn --minify --isolate --stats`
(`--paths` / `--ignore` can be repeated)

## API

```ts
import { bundle, bundleString, inspect } from "lua-forge";

// bundle from an entry file (writes the file if output is set)
const code = await bundle({
  entry: "client/main.lua",
  output: "dist/client.lua",
  mode: "flat",
  ignoredModuleNames: ["json"],
});

// bundle from a source string
const out = await bundleString(`local f = require("util")`, { root: "." });

// dependency graph only
const graph = await inspect({ entry: "server/main.lua" });
```

## Config

See [`lua-forge.config.example.ts`](./lua-forge.config.example.ts)

| field | default | description |
| --- | --- | --- |
| `entry` | — | entry file |
| `output` | — | output path |
| `mode` | `auto` | `auto` \| `flat` \| `runtime` |
| `circular` | `error` | `error` \| `runtime-fallback` (when flat hits a circular require) |
| `entries` | — | multi-entry build (e.g. client/server) |
| `paths` | `["?", "?.lua", "modules/?.lua"]` | package.path-style patterns |
| `root` | entry's dir | base dir for resolution |
| `ignoredModuleNames` | `[]` | modules left for the runtime to require itself |
| `metadata` | `false` | `false` (production) \| `true` \| `"debug"` — never leaks an absolute path |
| `minify` | `false` | light minify (strips comments/blank lines) |
| `isolate` | `false` | do not fall back to the global require |
| `luaVersion` | `5.4` | `5.4` \| `5.3` \| `LuaJIT` |
| `target` | `fivem` | `fivem` \| `generic` |
| `runtimeRequire` | — | Lua expression to require modules that are not bundled |
| `resolveHook` | — | custom resolution |
| `dynamicRequireHook` | — | handle `require(var)` |
| `persistentCache` | `false` | path to store the parse cache (keyed by content hash) |

## Output modes

**auto** (default) — picks flat when there is no circular require; on a circular require it follows `circular`
(`error` = stop and report the cycle, `runtime-fallback` = switch to runtime automatically)

**flat** — orders modules dependency-first, each module becomes a local var.
No runtime loader, smaller, faster at resource start.
Cannot be used with circular requires (errors, or falls back per `circular`).

**runtime** — has `__bundle_require` + module factories + a loaded cache (fast path),
plus localized globals (`type`/`tostring`/`error`); supports circular requires.

## FiveM: no global require

FiveM (CfxLua) has no global `require` — so lua-forge builds its own require runtime
(`__bundle_require` in runtime mode / inline vars in flat mode). The output therefore **does not rely on a global `require`**.

Modules that are not bundled (listed in `ignoredModuleNames` or required dynamically):
- `target: "fivem"` (default) → calling it raises a **clear error** with the module name (no crash from calling nil)
- if you have your own loader, set `runtimeRequire`, e.g. `"_G.myloader"` or `"exports.x.require"`
- `target: "generic"` → uses the normal global `require` (standard Lua)

## Dev

```bash
npm install
npm test
npm run build      # -> dist/
npm run typecheck
```
