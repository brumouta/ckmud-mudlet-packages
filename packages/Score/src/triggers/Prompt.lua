-- Append the room's gravity and your maximum to the prompt line. cecho on a
-- trigger line appends to it, so this lands right after the mud's prompt.
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local Room = ck:get_table("Room")

if not ck:feature("score.prompt_gravity") then
    return
end

local grav = Room.Gravity
local max = Player.MaxGravity
if not grav or not max then
    return -- nothing useful to show until MSDP has both
end

-- At or above your max is where training stops paying off; flag it
local colour = (grav >= max) and "green" or "red"
cecho("[<" .. colour .. ">" .. grav .. "<white>/<red>" .. max .. "x G<white>]")
