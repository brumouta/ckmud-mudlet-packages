-- This event fires every single Prompt
-- Vendored (trimmed) from CK's Prompt_Events.lua
local ck = require("__PKGNAME__")
local API = ck:get_table("API")
local PromptFlags = ck:get_table("PromptFlags")
local Toggles = ck:get_table("Toggles")
local Times = ck:get_table("API.Times")
local MSDP = ck:get_table("API.MSDP")


Times:create("prompt")

local function PlayerLoad()
    if API:is_connected(true) then
        raiseEvent("CH.onPlayerReload")
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
registerNamedEventHandler("__PKGNAME__", "CH:PromptWatchUninstall", "sysUninstallPackage", function(_, name)
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

registerNamedTimer("__PKGNAME__", "CH:LastPrompt", 8, LastPrompt, true)

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

    -- All flags since last prompt should be cleared so next prompt we can take action
    ck:clear_table(PromptFlags)
end

registerNamedEventHandler("__PKGNAME__", "onPrompt", "CH.onPrompt", onPrompt)

registerNamedEventHandler("__PKGNAME__", "CH:PlayerReload", "sysLoadEvent", function(event)
    PlayerLoad()
end)
