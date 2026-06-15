local a = require("circular.a")

local b = {}

b.name = "b"

function b.pong()
  return "b->" .. tostring(a.name)
end

return b
