-- Core API helpers, vendored (trimmed) from CK's LIBS.lua
local ck = require("__PKGNAME__")
local Times = ck:get_table("API.Times")
local Toggles = ck:get_table("Toggles")
local API = ck:get_table("API")
local PromptCounters = ck:get_table("PromptCounters")
local PromptFlags = ck:get_table("PromptFlags")
local Player = ck:get_table("Player", { Attacks = {} })
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")

ck:define_constant("name", "???")

function Player:get_health()
    if Player.Pl and Player.MaxPl then
        return math.floor(Player.Pl / Player.MaxPl * 100)
    end
    return 100 -- Lie So prompt works on first login
end

function Player:get_energy()
    return math.floor(Player.Ki / Player.MaxKi * 100)
end

function Player:get_stamina()
    if not API:has_fatigue() then
        return 100
    end
    return math.floor(Player.Fatigue / Player.MaxFatigue * 100)
end

function API:RESET_ALL()
    State:set(State.ALLSTOP)
    API.SendQueue:clear()
    Mode:switch()
    State:set()
end

function API:setName(name)
    Player.name = name
    local old_name = ck:constant("name")
    if old_name == "???" then
        ck:set_constant("name", name)
    elseif old_name ~= name then
        cecho(f " <Red>Error: Named Changed from {old_name}, use `AL constant name=\"{name}\"`")
    end
end

function API:getName()
    return Player.name or ck:constant("name")
end

function API:get_gravity(training)
    local max_gravity = Player.MaxGravity or 2
    local max_pl = Player.MaxPl or Player.Pl
    if training then
        return math.min(math.floor((1 / 5000) * 0.06 * max_pl), max_gravity - 1)
    else
        return max_gravity - 1
    end
end

function API:cmd_stack_empty()
    -- I might move this in the future
    return AL.cmd_stack == 0
end

function API:cmd_stack()
    return AL.cmd_stack
end

function API:status_ok()
    return Player:get_health() >= 50 and Player:get_energy() >= 50 and Player:get_stamina() >= 50
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
    echo("[ Autolearn ] - Feature DB Compaction Complete.\n")
end

local function compact_constdb()
    local names = ck:constant_names()
    db:delete(ck.db.schema.Constants, db:not_in(ck.db.schema.Constants.name, names))
    echo("[ Autolearn ] - Constants DB Compaction Complete.\n")
end

registerNamedEventHandler("__PKGNAME__", "AL:CompactDB", "sysExitEvent", function(event)
    compact_constdb()
    compact_featuredb()
end)

function API:not_fighting()
    -- If we haven't been fighting for 3 prompts then we are not fighting
    return not PromptCounters.fighting and not Toggles.fighting and not PromptFlags.Target
end

function API:is_connected(ignore_prompt)
    local _, _, connected = getConnectionInfo()
    return (ignore_prompt or Toggles.firstprompt == true) and connected == true
end

function Times:last(name)
    return getStopWatchTime("AL." .. name)
end

function Times:reset(name)
    resetStopWatch("AL." .. name)
end

function PromptCounters:active(name)
    return PromptCounters[name] ~= nil
end

function API:add_attack(name, cost, dmg, is_ubs, cooldown, count, extra)
    local extra_dict = {}
    for _, k in ipairs(extra or {}) do
        extra_dict[k] = true
    end
    Player.Attacks[name] = { cost, dmg, is_ubs, cooldown or 1, count or 1, extra_dict }
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

function API:send_multi(cmds)
    for _, cmd in ipairs(cmds:split(";")) do
        send(cmd)
    end
end
