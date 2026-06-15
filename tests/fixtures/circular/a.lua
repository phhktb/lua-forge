local b = require("circular.b")

local a = {}

function a.ping()
  return "a->" .. b.name
end

a.name = "a"

return a
