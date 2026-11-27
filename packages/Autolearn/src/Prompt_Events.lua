-- This event fires every single Prompt
-- Vendored (trimmed) from CK's Prompt_Events.lua
local ck = AL.ck
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local PromptFlags = ck:get_table("PromptFlags")
local PromptCounters = ck:get_table("PromptCounters")
local State = ck:get_table("API.State")
local Toggles = ck:get_table("Toggles")
local Times = ck:get_table("API.Times")
local MSDP = ck:get_table("API.MSDP")
local Target = ck:get_table("Target")


Times:create("fight")
Times:create("fightfinished")
Times:create("prompt")

local function PlayerLoad()
    if API:is_connected(true) then
        raiseEvent("AL.onPlayerReload")
    end
end

local function decPromptCounters()
    for k, v in pairs(PromptCounters) do
        if k ~= "active" then
            if v ~= nil then
                if v <= 1 then
                    PromptCounters[k] = nil
                elseif v ~= nil then
                    PromptCounters[k] = v - 1
                end
            end
        end
    end
end


local function onPrompt()
    Times:reset("prompt")

    -- Lets check if MSDP is up2date
    if Toggles.ticked_once then
        local last_update = MSDP:last_update()
        if last_update > ck:constant("MSDP.reconnect_timeout") then
            cecho(
            "<red>!<yellow>!<red>!<yellow>!<white> Reconnecting to fix CKMud MSDP feed <yellow>!<red>!<yellow>!<red>!\n")
            reconnect()
            Toggles.ticked_once = false
        elseif last_update > ck:constant("MSDP.timeout") then
            if ck:feature("MSDP.debug") then
                cecho(
                "<red>!<yellow>!<red>!<yellow>!<white> Re-Subscribing to MSDP events<yellow>!<red>!<yellow>!<red>!\n")
            end
            MSDP:report_names()
            Toggles.ticked_once = false
        end
    end

    Toggles.firstprompt = true

    if not PromptFlags.Target then
        Player.Target = nil
        Player.Target_Full = nil
    end

    if PromptFlags.Target or Target.name ~= "" then
        -- How long to wait until we start doing notfighting events
        PromptCounters.fighting = 3
        raiseEvent("AL.onFightingPrompt")
    end

    if Toggles.fighting and not (PromptFlags.Target or Target.name ~= "") then
        -- We just stopped a fight
        Toggles.fighting = false
        raiseEvent("AL.onFinishedFighting")
    end
    -- We haven't been in combat for quite a while
    if API:not_fighting() then
        -- Only when we are damn sure we are not fighting
        raiseEvent("AL.onNotFightingPrompt")
    end
    -- All flags since last prompt should be cleared so next prompt we can take action
    ck:clear_table(PromptFlags)
    decPromptCounters()
end

registerNamedEventHandler("Autolearn", "onPrompt", "AL.onPrompt", onPrompt)

local function onNotFightingPrompt()
    -- Handle Send Queue
    ck:get_table("API.SendQueue"):trySendNow()
    raiseEvent("AL.notFighting")
end

registerNamedEventHandler("Autolearn", "onNotFightingPrompt", "AL.onNotFightingPrompt", onNotFightingPrompt)

local function onFightingPrompt(val)
    if State:check(State.CRAFTING, true) or State:check(State.BUFFING, true) or State:check(State.SENSE, true) then
        State:set(State.NORMAL)
    end
    raiseEvent("AL.fighting")
end

registerNamedEventHandler("Autolearn", "onFightingPrompt", "AL.onFightingPrompt", onFightingPrompt)

local function onFinishedFighting(event)
    Times:reset("fightfinished")
    raiseEvent("AL.finishedFighting")
end

registerNamedEventHandler("Autolearn", "onFinishedFighting", "AL.onFinishedFighting", onFinishedFighting)

registerNamedEventHandler("Autolearn", "AL:PlayerReload", "sysLoadEvent", function(event)
    PlayerLoad()
end)
