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
  return
end
echo("[ Autolearn ] - Training first, in this order: " .. now .. "\n")

-- Check the names against your skills, so typos don't go unnoticed
local unknown = AL.API.Learning.check_priority(now)
if unknown == nil then
  cecho("<yellow>[ Autolearn ] - Can't check the names yet: type `learn` and then `AL priority` again.\n")
elseif #unknown > 0 then
  for _, u in ipairs(unknown) do
    local hint = u.suggestion and (" - did you mean '" .. u.suggestion .. "'?") or ""
    cecho("<yellow>[ Autolearn ] - Not one of your skills: '" .. u.name .. "'" .. hint .. "\n")
  end
  cecho("<yellow>[ Autolearn ] - Those are ignored. Names are the ones `learn` shows.\n")
else
  cecho("<green>[ Autolearn ] - All of them are skills you have.\n")
end
