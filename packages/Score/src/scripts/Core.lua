-- Core API helpers, vendored (trimmed) from CK's LIBS.lua
local ck = require("__PKGNAME__")
local API = ck:get_table("API")
local Player = ck:get_table("Player")

ck:get_table("Player.Stats")
ck:get_table("Player.BaseStats")

function API:constant(name)
    return ck:constant(name)
end

function API:feature(name)
    return ck:feature(name)
end

function API:getRace()
    return Player.race or "???"
end

function API:isAndroid(race)
    return (race or self:getRace()) == "Android"
end

function API:isBioDroid(race)
    return (race or self:getRace()) == "BioAndroid"
end

local function compact_featuredb()
    local names = ck:feature_names()
    db:delete(ck.db.schema.Toggles, db:not_in(ck.db.schema.Toggles.name, names))
    echo("[ Score ] - Feature DB Compaction Complete.\n")
end

local function compact_constdb()
    local names = ck:constant_names()
    db:delete(ck.db.schema.Constants, db:not_in(ck.db.schema.Constants.name, names))
    echo("[ Score ] - Constants DB Compaction Complete.\n")
end

registerNamedEventHandler("__PKGNAME__", "SC:CompactDB", "sysExitEvent", function(event)
    compact_constdb()
    compact_featuredb()
end)

function API:is_connected()
    local _, _, connected = getConnectionInfo()
    return connected == true
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
    if changes and self:is_connected() then
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
