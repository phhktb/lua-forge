# lua-forge

A general-purpose Lua bundler — combine many Lua files into one. Fast, lightweight, easy to maintain.
Use it for any Lua runtime: game frameworks, embedded Lua, tooling, or plain standalone scripts.

## Why

- Fast builds (content/stat/resolve/parse caching)
- Two output modes: `runtime` (handles circular requires) and `flat` (smallest, production-ready)
- Clear errors: module name + importer + line/column + searched paths
- Usable from both the CLI and the API
- No app-specific logic; no obfuscation/minification by default

## Install

```bash
npm install lua-forge
```

## Writing Lua modules

Author your code as plain Lua files. A module returns a value (usually a table);
other files pull it in with `require("module.name")`. Dots map to folders,
exactly like Lua's `package.path` (`require("modules.format")` -> `modules/format.lua`).

```
src/
├── main.lua                 -- entry
├── utils.lua
├── shared/config.lua
└── modules/format.lua
```

```lua
-- src/modules/format.lua
local format = {}

function format.bold(text)
  return "**" .. text .. "**"
end

return format            -- the module's return value
```

```lua
-- src/utils.lua
local format = require("modules.format")   -- resolved & inlined by the bundler

local utils = {}

function utils.greet(name)
  return format.bold("hello " .. name)
end

return utils
```

```lua
-- src/main.lua (entry — no return needed)
local utils  = require("utils")
local config = require("shared.config")

print(utils.greet(config.name))
```

Build it into a single file:

```bash
lua-forge build --entry src/main.lua --out build/app.lua --root src
```

In the generated bundle, every `require("...")` that the bundler resolved is
replaced — there is no runtime `require` left for those. Host-provided globals
(anything that is not a `require` call) are left untouched.

Run it like any Lua file:

```bash
lua build/app.lua
```

### Modules not bundled (ignored / dynamic)

Some modules you may want to leave out of the bundle (a host-provided library,
a C module, a dynamically-named require). List those names in `ignoredModuleNames`.

How they are required at runtime depends on `target`:

- `target: "generic"` (default) — routed to the global `require` (standard Lua)
- `target: "fivem"` (or any host without a global `require`) — raises a clear
  error naming the missing module, unless you provide a loader via `runtimeRequire`

```bash
lua-forge build --entry src/main.lua --out build/app.lua \
  --root src --ignore json --require-fn "_G.myloader"
```

Inside the bundle the ignored `require("json")` becomes `__lf_require("json")`,
which routes to your `runtimeRequire` expression (or the global `require` by default).

## CLI

```bash
# build (default mode = auto: flat when there is no circular require)
lua-forge build --entry src/main.lua --out build/app.lua

# multi-entry: build several outputs from one config
lua-forge build --config lua-forge.config.ts

# inspect the dependency graph
lua-forge inspect --entry src/main.lua --root .

# benchmark runtime vs flat
lua-forge benchmark --entry src/main.lua --runs 50
```

Main flags: `--entry --out --config --mode flat|runtime|auto --target generic|fivem --metadata [true|false|debug] --circular error|runtime-fallback --root --paths --ignore --lua --require-fn --minify --isolate --stats`
(`--paths` / `--ignore` can be repeated)

## API

```ts
import { bundle, bundleString, inspect } from "lua-forge";

// bundle from an entry file (writes the file if output is set)
const code = await bundle({
  entry: "src/main.lua",
  output: "build/app.lua",
  mode: "flat",
  ignoredModuleNames: ["json"],
});

// bundle from a source string
const out = await bundleString(`local f = require("util")`, { root: "." });

// dependency graph only
const graph = await inspect({ entry: "src/main.lua" });
```

## Config

See [`lua-forge.config.example.ts`](./lua-forge.config.example.ts)

| field | default | description |
| --- | --- | --- |
| `entry` | — | entry file |
| `output` | — | output path |
| `mode` | `auto` | `auto` \| `flat` \| `runtime` |
| `circular` | `error` | `error` \| `runtime-fallback` (when flat hits a circular require) |
| `entries` | — | multi-entry build (several outputs from one config) |
| `paths` | `["?", "?.lua", "modules/?.lua"]` | package.path-style patterns |
| `root` | entry's dir | base dir for resolution |
| `ignoredModuleNames` | `[]` | modules left for the runtime to require itself |
| `metadata` | `false` | `false` (production) \| `true` \| `"debug"` — never leaks an absolute path |
| `minify` | `false` | light minify (strips comments/blank lines) |
| `isolate` | `false` | do not fall back to the global require |
| `luaVersion` | `5.4` | `5.4` \| `5.3` \| `LuaJIT` |
| `target` | `generic` | `generic` \| `fivem` (a host without a global require) |
| `runtimeRequire` | — | Lua expression to require modules that are not bundled |
| `resolveHook` | — | custom resolution |
| `dynamicRequireHook` | — | handle `require(var)` |
| `persistentCache` | `false` | path to store the parse cache (keyed by content hash) |

## Output modes

**auto** (default) — picks flat when there is no circular require; on a circular require it follows `circular`
(`error` = stop and report the cycle, `runtime-fallback` = switch to runtime automatically)

**flat** — orders modules dependency-first, each module becomes a local var.
No runtime loader, smaller, faster to load.
Cannot be used with circular requires (errors, or falls back per `circular`).

**runtime** — has `__bundle_require` + module factories + a loaded cache (fast path),
plus localized globals (`type`/`tostring`/`error`); supports circular requires.

## Hosts without a global `require`

Some Lua hosts (for example FiveM's CfxLua) have no global `require`. lua-forge
builds its own require runtime (`__bundle_require` in runtime mode / inline vars
in flat mode), so the output **does not rely on a global `require`** for bundled
modules.

For such a host set `target: "fivem"` (or any value other than `generic`).
Then any non-bundled module raises a clear error instead of crashing on a nil
call — provide `runtimeRequire` (e.g. `"_G.myloader"` or `"exports.x.require"`)
if you have your own loader. Point the host at the single bundled file, e.g. in
FiveM:

```lua
-- fxmanifest.lua
client_scripts { 'build/client.lua' }
server_scripts { 'build/server.lua' }
```

## Dev

```bash
npm install
npm test
npm run build      # -> dist/
npm run typecheck
```
