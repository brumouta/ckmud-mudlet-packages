-- AL priority                       - show the skills trained first
-- AL priority multiform, rescue     - train these first, in this order
-- AL priority clear                 - back to the usual order
local ck = require("__PKGNAME__")
local list = matches[2]
if list then
  list = list:gsub("^%s+", ""):gsub("%s+$", "")
  if list:lower() == "clear" or list:lower() == "none" then list = "" end
  ck:set_constant("learning.priority", list)
end
local now = ck:constant("learning.priority")
if now == "" then
  echo("[ Autolearn ] - No priority: skills train in the usual order. Set one with `AL priority multiform, kamehameha`\n")
else
  echo("[ Autolearn ] - Training first, in this order: " .. now .. "\n")
end
