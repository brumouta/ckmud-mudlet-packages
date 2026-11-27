-- Stats come straight from the shared MSDP package (it subscribes, converts and shares the values
-- for every CKMud package): AL.Player, AL.Room and AL.Target read through to MSDP.Player,
-- MSDP.Room and MSDP.Target, so the rest of Autolearn keeps reading Player.MaxPl, Room.Gravity,
-- Target.name, ... while holding only its own data (skills, prompt status, name, race).
local ck = AL.ck
local Player = ck:get_table("Player")
local Room = ck:get_table("Room")
local Target = ck:get_table("Target")
local MSDP = ck:get_table("API.MSDP")

local function shared() return rawget(_G, "MSDP") end

local function through(t, kind)
    setmetatable(t, { __index = function(_, k)
        local M = shared()
        local src = M and M[kind]
        if src then return src[k] end
    end })
end

-- Autolearn 4.0.0-4.0.2 copied the values in: drop those copies (a reinstall keeps AL), or they'd
-- hide the live ones. Its own fields stay.
local OWN = { name = true, race = true, Status = true, Rage = true, Skills = true, Attacks = true,
    Target = true, Target_Full = true }
do
    local M = shared()
    for k, v in pairs(Player) do
        if not OWN[k] and type(v) ~= "function" and (k == "Stats" or k == "BaseStats" or (M and M.Player[k] ~= nil)) then
            Player[k] = nil
        end
    end
    for _, t in ipairs({ Room, Target }) do
        for k in pairs(t) do if not k:find("^__") then t[k] = nil end end
    end
    AL.cmd_stack = nil
end
through(Player, "Player")
through(Room, "Room")
through(Target, "Target")

function AL.API:cmd_stack()
    local M = shared()
    return M and M.cmd_stack
end
function AL.API:cmd_stack_empty() return self:cmd_stack() == 0 end

local warned = false
local function needShared()
    if shared() or warned then return end
    warned = true
    cecho("\n<red>[ Autolearn ] needs the MSDP package for your stats. Install MSDP.mpackage from the " ..
              "ckmud-mudlet-packages release, then reconnect.\n")
end

function MSDP:last_update()
    local M = shared()
    if M then return M:last_update() end
    return getEpoch() - tonumber((msdp and msdp.UPDATE_EPOCH) or 0)
end

function MSDP:report_names()
    local M = shared()
    if M then M:report() else needShared() end
end

-- AL.tick on every server update, for anything that hooks into it
registerNamedEventHandler("Autolearn", "MSDP tick", "MSDP.tick", function() raiseEvent("AL.tick") end)
registerNamedEventHandler("Autolearn", "MSDP REPORT", "sysConnectionEvent", function() tempTimer(2, needShared) end)
registerNamedEventHandler("Autolearn", "MSDP Player Reload", "AL.onPlayerReload", function() MSDP:report_names() end)
tempTimer(5, needShared)
