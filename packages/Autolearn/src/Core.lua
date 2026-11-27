-- Core API helpers, vendored (trimmed) from CK's LIBS.lua
local ck = AL.ck
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


function API:not_fighting()
    -- If we haven't been fighting for 3 prompts then we are not fighting
    return not PromptCounters.fighting and not Toggles.fighting and not PromptFlags.Target
end

function API:is_connected(ignore_prompt)
    local _, _, connected = getConnectionInfo()
    return (ignore_prompt or Toggles.firstprompt == true) and connected == true
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


function API:send_multi(cmds)
    for _, cmd in ipairs(cmds:split(";")) do
        send(cmd)
    end
end
