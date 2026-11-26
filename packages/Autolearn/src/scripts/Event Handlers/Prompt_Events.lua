-- This event fires every single Prompt
-- Vendored (trimmed) from CK's Prompt_Events.lua
local ck = require("__PKGNAME__")
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

-- Warn when the game keeps sending lines but none of them is a prompt we recognise ([Pl: <n> | ...]).
-- Being idle sends nothing, so it never warns then, nor in the moment between a prompt showing and its
-- trigger running. Warns once; the next recognised prompt arms it again.
local NO_PROMPT_SECS, NO_PROMPT_LINES = 300, 100
local promptWatch = { lines = 0, warned = false }
_G.CKPromptLineTriggers = _G.CKPromptLineTriggers or {}
if _G.CKPromptLineTriggers["__PKGNAME__"] then killTrigger(_G.CKPromptLineTriggers["__PKGNAME__"]) end
_G.CKPromptLineTriggers["__PKGNAME__"] = tempRegexTrigger("^", function() promptWatch.lines = promptWatch.lines + 1 end)
registerNamedEventHandler("__PKGNAME__", "AL:PromptWatchUninstall", "sysUninstallPackage", function(_, name)
    if name == "__PKGNAME__" and _G.CKPromptLineTriggers["__PKGNAME__"] then
        killTrigger(_G.CKPromptLineTriggers["__PKGNAME__"])
        _G.CKPromptLineTriggers["__PKGNAME__"] = nil
    end
end)

local function LastPrompt()
    if promptWatch.warned or not API:is_connected() then return end
    if API.Times:last("prompt") > NO_PROMPT_SECS and promptWatch.lines >= NO_PROMPT_LINES then
        promptWatch.warned = true
        cecho("\n<red>[ __PKGNAME__ ] <white>No prompt recognised in the last " .. promptWatch.lines ..
            " lines: bot features need the game prompt to start with <yellow>[Pl: <number> | ...\n")
    end
end

registerNamedTimer("__PKGNAME__", "AL:LastPrompt", 8, LastPrompt, true)

local function onPrompt()
    Times:reset("prompt")
    promptWatch.lines, promptWatch.warned = 0, false

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

registerNamedEventHandler("__PKGNAME__", "onPrompt", "AL.onPrompt", onPrompt)

local function onNotFightingPrompt()
    -- Handle Send Queue
    ck:get_table("API.SendQueue"):trySendNow()
    raiseEvent("AL.notFighting")
end

registerNamedEventHandler("__PKGNAME__", "onNotFightingPrompt", "AL.onNotFightingPrompt", onNotFightingPrompt)

local function onFightingPrompt(val)
    if State:check(State.CRAFTING, true) or State:check(State.BUFFING, true) or State:check(State.SENSE, true) then
        State:set(State.NORMAL)
    end
    raiseEvent("AL.fighting")
end

registerNamedEventHandler("__PKGNAME__", "onFightingPrompt", "AL.onFightingPrompt", onFightingPrompt)

local function onFinishedFighting(event)
    Times:reset("fightfinished")
    raiseEvent("AL.finishedFighting")
end

registerNamedEventHandler("__PKGNAME__", "onFinishedFighting", "AL.onFinishedFighting", onFinishedFighting)

registerNamedEventHandler("__PKGNAME__", "AL:PlayerReload", "sysLoadEvent", function(event)
    PlayerLoad()
end)
