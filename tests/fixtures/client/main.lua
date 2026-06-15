local utils = require("utils")
local config = require("shared.config")
local json = require("json")

local function start()
  print(utils.greet(config.name))
  return json.encode({ ok = true })
end

start()
