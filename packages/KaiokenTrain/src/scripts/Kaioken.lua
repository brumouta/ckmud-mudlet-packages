-- Vendored from CK's Bots/Kaioken.lua. Changes: standalone package module,
-- KT-prefixed timer name, and enter() no longer hides the status output
-- (CK's status-gagging triggers are not part of this package).
local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local kaio = ck:get_table("API.Kaioken", {
    triggers = {},
    max = 120,
})
local API = ck:get_table("API")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")

ck:define_constant("kaioken.drink_cmd", "drink tears")

local function exit()
    -- Delete timer
    deleteNamedTimer("__PKGNAME__", "KT:Kaioken")
    -- Kill Triggers
    for _, id in ipairs(kaio.triggers) do
        killTrigger(id)
    end
    kaio.triggers = {}
    print("Kaioken Training Mode Disabled!!!")
end

---@diagnostic disable-next-line: unused-function
local function do_kaioken()
    if not API:is_connected() then
        -- Don't do anything unless we are connected and have a prompt
        return
    end
    if State:is(State.NORMAL) then
        local mkaioken = Player.MKaioken or 0
        local goal = kaio.max - 8
        local target = math.min(kaio.max, mkaioken + 9)

        if mkaioken >= goal then
            -- The usable kaioken ceiling grows as the character progresses,
            -- so the max captured earlier may be stale. Only declare mastery
            -- once a fresh 'kaioken getmax' reply confirms the goal; if the
            -- ceiling grew, the goal grows with it and training continues.
            if kaio.confirmed_done == mkaioken then
                send(f "kaioken {goal}")
                echo("You have mastered Kaioken completely!\n")
                Mode:switch(Mode.Interactive)
            else
                send("kaioken getmax", false)
            end
        elseif Player.Fatigue / Player.MaxFatigue < 0.20 then
            State:set(State.REST)
            send("kaioken")
            send("land") -- can't sleep while flying
            send("sleep")
        elseif Player.Kaioken < target then
            -- Raise the kaioken
            send(f "kaioken {target}")
        elseif Player.Thirst < 40 then
            send(ck:constant("kaioken.drink_cmd"))
        end
    elseif State:is(State.REST) then
        if API:is_rested() then
            send("wake")
            State:set(State.NORMAL)
        end
    end
end

local function enter()
    -- Catch the max kaioken possible for the character. Kept alive for the
    -- whole training session (killed in exit) because the ceiling grows as
    -- the character progresses and gets re-checked whenever the goal is hit.
    kaio.confirmed_done = nil
    table.insert(kaio.triggers, tempRegexTrigger("^Syntax: Kaioken 1-([0-9]+)$",
        function()
            kaio.max = tonumber(matches[2])
            if (Player.MKaioken or 0) >= kaio.max - 8 then
                -- Fresh reply confirms there is nothing left to master
                kaio.confirmed_done = Player.MKaioken
            end
            -- So nobody sees it
            gagLine()
        end
    ))
    -- Silently ask for kaioken
    send("kaioken getmax", false)

    if Player.MKaioken == nil then
        send("status", false)
    end

    -- Change Mode
    Mode:switch(Mode.Kaioken, exit)

    print("Kaioken Training Mode Enabled!!!, Try to hang out in an isolation chamber")
    -- Install a timer
    registerNamedTimer("__PKGNAME__", "KT:Kaioken", 4, do_kaioken, true)
end

function kaio:toggle()
    if Mode:is(Mode.Kaioken) then
        Mode:switch(Mode.Interactive)
    else -- Its off
        -- Change Mode
        enter()
    end
end
