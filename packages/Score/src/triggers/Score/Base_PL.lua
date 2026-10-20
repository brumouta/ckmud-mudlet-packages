-- The mud no longer sends BASE_PL over MSDP, but the score sheet prints it.
-- This line comes well before the anchors that render the extras.
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")

local raw = multimatches[2][2]:gsub(",", "")
local base_pl = tonumber(raw)
if base_pl then
    Player.BasePl = base_pl
end
