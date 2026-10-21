-- MSDP comes from the shared MSDP package (it subscribes, converts and shares the
-- values for every CKMud package). This bridge copies those values into this
-- package's own Player/Room/Target tables, so the rest of the package keeps reading
-- Player.MaxPl, Room.Gravity, SC.cmd_stack, ... exactly as before.
local ck = require("__PKGNAME__")
local ROOT = ck:get_table()
local Player = ck:get_table("Player")
local Room = ck:get_table("Room")
local Target = ck:get_table("Target")
local MSDP = ck:get_table("API.MSDP")
local Toggles = ck:get_table("Toggles")

-- So they will be there for msdp
ck:get_table("Player.Stats")
ck:get_table("Player.BaseStats")
ck:define_feature("MSDP.debug", false)
ck:define_constant("MSDP.timeout", 10)
ck:define_constant("MSDP.reconnect_timeout", 120)

local function shared()
    return rawget(_G, "MSDP")
end

local warned = false
local function needShared()
    if shared() or warned then
        return
    end
    warned = true
    cecho("\n<red>[ __PKGNAME__ ] needs the MSDP package for your stats. Install MSDP.mpackage from the " ..
              "ckmud-mudlet-packages release, then reconnect.\n")
end

local DEST = {
    Player = function() return Player end,
    Stats = function() return Player.Stats end,
    BaseStats = function() return Player.BaseStats end,
    Room = function() return Room end,
    Target = function() return Target end,
}

local function copy(kind, field, value)
    if kind == "MSDP" and field == "cmd_stack" then
        ROOT.cmd_stack = value
    elseif DEST[kind] then
        DEST[kind]()[field] = value
    end
end

local function copyAll()
    local M = shared()
    if not M then
        return
    end
    for field, value in pairs(M.Player) do
        if type(value) ~= "table" then copy("Player", field, value) end
    end
    for field, value in pairs(M.Player.Stats) do copy("Stats", field, value) end
    for field, value in pairs(M.Player.BaseStats) do copy("BaseStats", field, value) end
    for field, value in pairs(M.Room) do copy("Room", field, value) end
    for field, value in pairs(M.Target) do copy("Target", field, value) end
    if M.cmd_stack ~= nil then copy("MSDP", "cmd_stack", M.cmd_stack) end
    if M.ticked then Toggles.ticked_once = true end
end

function MSDP:last_update()
    local M = shared()
    if M then
        return M:last_update()
    end
    return getEpoch() - tonumber((msdp and msdp.UPDATE_EPOCH) or 0)
end

function MSDP:report_names()
    local M = shared()
    if M then
        M:report()
    else
        needShared()
    end
end

registerNamedEventHandler("__PKGNAME__", "MSDP changed", "MSDP.changed", function(_, kind, field, value)
    copy(kind, field, value)
end)

-- Track Updates, fire off a SC.tick event for hud to hook into.
registerNamedEventHandler("__PKGNAME__", "MSDP tick", "MSDP.tick", function()
    if not Toggles.ticked_once and ck:feature("MSDP.debug") then
        cecho(f "<yellow>Received MSDP Update Epoch...\n")
    end
    Toggles.ticked_once = true
    raiseEvent("SC.tick")
end)

registerNamedEventHandler("__PKGNAME__", "MSDP loaded", "MSDP.loaded", copyAll)

-- The MSDP package subscribes on connect; we only reset our tick flag
registerNamedEventHandler("__PKGNAME__", "MSDP REPORT", "sysConnectionEvent", function()
    Toggles.ticked_once = false
    tempTimer(2, needShared)
end)

registerNamedEventHandler("__PKGNAME__", "MSDP Player Reload", "SC.onPlayerReload", function()
    Toggles.ticked_once = false
    MSDP:report_names()
end)

-- Pick up whatever the MSDP package already has (it may have loaded first)
copyAll()
tempTimer(5, needShared)
