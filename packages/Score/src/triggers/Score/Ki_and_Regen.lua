-- Replace the percentage line with absolute Ki and regen per tick
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local fmt = ck:get_table("math")

if not ck:feature("score.regen") or not Player.MaxKi then
    return
end

local pct = tonumber(multimatches[2][3])
local regen = math.floor(Player.MaxKi * pct / 100)
Player.KiRegen = regen
gagLine()

cecho(string.format('\n<dim_gray>Ki<white>:    %-27s<dim_gray> KI REGEN<white>: %s\n',
    fmt.format(Player.Ki), fmt.format(regen)))
