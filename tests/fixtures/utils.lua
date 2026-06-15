local format = require("modules.format")

local utils = {}

function utils.greet(name)
  return format.bold("hello " .. name)
end

return utils
