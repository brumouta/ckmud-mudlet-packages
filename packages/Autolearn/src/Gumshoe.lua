-- Steps aside for Gumshoe's `gum repeat` (gumshoe.xml): when a repeat case is about to start,
-- learning pauses (any fight or walk is finished first, and you're woken up); once Gumshoe is back
-- at Jaco after the case, learning starts again and heads back the way resting does: the
-- learning.recall_isolation recall, rest, then the start path to the target.
-- AL feature learning.pause_for_gumshoe off turns this off.
local ck = AL.ck
local learn = ck:get_table("API.Learning")
local API = ck:get_table("API")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")

ck:define_feature("learning.pause_for_gumshoe", true)

local function say(msg) cecho("<cyan>[ Autolearn ] - <white>" .. msg .. "\n") end
local function gum() return type(_G.gum) == "table" and _G.gum or nil end

-- What was running when Gumshoe asked: { target, path }
learn.gumshoe_paused = learn.gumshoe_paused or nil

local function on_starting()
    if not Mode:is(Mode.Learning) or not ck:feature("learning.pause_for_gumshoe") then return end
    local g = gum()
    local walking, resting = State:is(State.SPEEDWALK), State:is(State.REST)
    learn.gumshoe_paused = { target = learn.target, path = learn.speedwalk }
    Mode:switch(Mode.Interactive) -- stops the learning timer and its triggers
    say("Paused for Gumshoe's case: learning carries on when it's done")
    if not learn:use_recall_rest() then
        say("<yellow>No way back from Jaco set: learning will stay off after the case. To come back by itself, " ..
            "set AL constant learning.recall_isolation and start with the path, e.g. autolearn elder n;n;w")
    end
    if not (g and g.hold) then return end
    g.hold("Autolearn")
    local waited = 0
    local function ready()
        -- let a fight end before Gumshoe walks (it gives up waiting after 3 minutes)
        if not API:not_fighting() and waited < 180 then
            waited = waited + 2
            return tempTimer(2, ready)
        end
        if resting then send("wake") end
        g.release("Autolearn")
    end
    if walking then
        -- the rest speedwalk ends with `sleep`: wake straight after it
        resting = true
        registerAnonymousEventHandler("sysSpeedwalkFinished", function() tempTimer(1, ready) end, true)
    else
        ready()
    end
end

local function on_done()
    local p = learn.gumshoe_paused
    if not p then return end
    learn.gumshoe_paused = nil
    if Mode:is(Mode.Learning) then return end -- started again by hand meanwhile
    learn:toggle(p.target, p.path)
    if not Mode:is(Mode.Learning) then return end
    if not learn:use_recall_rest() then
        Mode:switch(Mode.Interactive)
        return say("<yellow>Gumshoe is done, but there's no way back from Jaco: autolearn " ..
            tostring(p.target) .. " " .. tostring(p.path or "") .. " from the training spot to carry on")
    end
    local g = gum()
    if g and g.rep then g.rep.claimed = "Autolearn" end -- instead of gum repeat wait's commands
    say("Gumshoe is done: back to learning (recall, rest, then the way back to " .. tostring(p.target) .. ")")
    learn:go_rest()
end

registerNamedEventHandler("Autolearn", "AL:GumshoeStarting", "gumshoe.repeat.starting", on_starting)
registerNamedEventHandler("Autolearn", "AL:GumshoeDone", "gumshoe.repeat.done", on_done)
