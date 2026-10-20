-- Androids: heat is the used part of the ki pool
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local fmt = ck:get_table("math")

if not ck:feature("score.regen") or not Player.MaxKi then
    return
end

local pct = tonumber(multimatches[2][3])
local dissipation = math.floor(Player.MaxKi * pct / 100)
Player.KiRegen = dissipation
gagLine()

cecho(string.format('\n<dim_gray>Heat<white>: %-25s<dim_gray> Dissipation<white>: %s\n',
    fmt.format(Player.MaxKi - Player.Ki), fmt.format(dissipation)))
