-- This event fires every single Prompt
-- Vendored (trimmed) from CK's Prompt_Events.lua
local ck = require("__PKGNAME__")
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local PromptFlags = ck:get_table("PromptFlags")
local Toggles = ck:get_table("Toggles")
local Times = ck:get_table("API.Times")
local MSDP = ck:get_table("API.MSDP")


Times:create("prompt")

local function PlayerLoad()
    if API:is_connected(true) then
        raiseEvent("KT.onPlayerReload")
    end
end

local function LastPrompt()
    if API:is_connected() then
        if API.Times:last("prompt") > 3600 then
            cecho("<red>!!!!!Prompt is not parsing file a bug!!!!!")
        end
    end
end

-- setup a timer so we always get a prompt in a reasonable time
registerNamedTimer("__PKGNAME__", "KT:LastPrompt", 8, LastPrompt, true)

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

    if not PromptFlags.Kaioken then
        Player.Kaioken = 0
    end

    -- All flags since last prompt should be cleared so next prompt we can take action
    ck:clear_table(PromptFlags)
end

registerNamedEventHandler("__PKGNAME__", "onPrompt", "KT.onPrompt", onPrompt)

registerNamedEventHandler("__PKGNAME__", "KT:PlayerReload", "sysLoadEvent", function(event)
    PlayerLoad()
end)
