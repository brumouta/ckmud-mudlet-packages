-- Replace the percentage line with absolute GodKi and regen per tick
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local fmt = ck:get_table("math")

if not ck:feature("score.regen") or not Player.MaxGK then
    return
end

local pct = tonumber(multimatches[2][3])
local regen = math.floor(Player.MaxGK * pct / 100)
Player.GKRegen = regen
gagLine()

cecho(string.format('\n<dim_gray>GodKi<white>: %-27s<dim_gray> GODKI REGEN<white>: %s\n',
    fmt.format(Player.GK), fmt.format(regen)))
