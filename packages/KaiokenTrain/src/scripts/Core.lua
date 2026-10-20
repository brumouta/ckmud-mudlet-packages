-- Core API helpers, vendored (trimmed) from CK's LIBS.lua
local ck = require("__PKGNAME__")
local Times = ck:get_table("API.Times")
local Toggles = ck:get_table("Toggles")
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")

function API:RESET_ALL()
    State:set(State.ALLSTOP)
    Mode:switch()
    State:set()
end

function API:is_rested()
    return (
        Player.GK == Player.MaxGK and
        Player.Ki == Player.MaxKi and
        Player.Fatigue == Player.MaxFatigue and
        Player.Pl == Player.MaxPl
    )
end

function API:constant(name)
    return ck:constant(name)
end

function API:feature(name)
    return ck:feature(name)
end

local function compact_featuredb()
    local names = ck:feature_names()
    db:delete(ck.db.schema.Toggles, db:not_in(ck.db.schema.Toggles.name, names))
    echo("[ KaiokenTrain ] - Feature DB Compaction Complete.\n")
end

local function compact_constdb()
    local names = ck:constant_names()
    db:delete(ck.db.schema.Constants, db:not_in(ck.db.schema.Constants.name, names))
    echo("[ KaiokenTrain ] - Constants DB Compaction Complete.\n")
end

registerNamedEventHandler("__PKGNAME__", "KT:CompactDB", "sysExitEvent", function(event)
    compact_constdb()
    compact_featuredb()
end)

function API:is_connected(ignore_prompt)
    local _, _, connected = getConnectionInfo()
    return (ignore_prompt or Toggles.firstprompt == true) and connected == true
end

function Times:last(name)
    return getStopWatchTime("KT." .. name)
end

function Times:reset(name)
    resetStopWatch("KT." .. name)
end

function API:check_msdp_mudlet_settings()
    local options = getConfig()
    local changes = false
    local wanted = {
        enableGMCP = false,
        enableMNES = true,
        enableMSDP = true,
        enableMSP = false,
        enableMSSP = false,
        enableMTTS = true
    }

    for name, value in pairs(wanted) do
        if options[name] ~= value then
            setConfig(name, value)
            changes = true
        end
    end
    if changes and self:is_connected(true) then
        cecho(
            "<red>!<yellow>!<red>!<yellow>!<white> Reconnecting to fix Mudlet Protocol Settings <yellow>!<red>!<yellow>!<red>!\n")
        reconnect()
    end
    return changes
end

registerNamedEventHandler("__PKGNAME__", "Enforce Protocols", "sysConnectionEvent", function()
    API:check_msdp_mudlet_settings()
end)

registerNamedEventHandler("__PKGNAME__", "Enforce Protocols on Install", "sysInstall", function(event, name)
    if name == "__PKGNAME__" then
        API:check_msdp_mudlet_settings()
    end
end)
