-- Automated chores: fishing and the recurring royal cook delivery quest.
-- Modes: fish | quest | both. In 'both', the quest preempts fishing (and
-- resting) when its cooldown is up, then fishing resumes.
local ck = require("__PKGNAME__")
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local Target = ck:get_table("Target")
local Chores = ck:get_table("API.Chores", {
    mode = "off",      -- off | fish | quest | both
    activity = "idle", -- idle | fishing | resting | quest | boss | rival
    quest = {},
})

ck:define_constant("chores.fishing_path", "")
ck:define_constant("chores.rest_path", "")
-- How to get to the royal cook. Like chores.grave_path it may include the
-- 'pursue royal cook' step itself, in which case the Roshi check is skipped.
ck:define_constant("chores.cook_path", "recall;focus 'instant' roshi")
ck:define_constant("chores.quest_period", 5)     -- minutes between deliveries
ck:define_constant("chores.recast_timeout", 120) -- seconds without a bite -> recast
ck:define_constant("chores.rest_below", 20)      -- rest when fatigue %% drops below
ck:define_constant("chores.boss_before", "")     -- commands before fighting a boss fish
ck:define_constant("chores.boss_attack", "")     -- attack to repeat during a boss fight
ck:define_constant("chores.boss_after", "")      -- commands after the boss dies
ck:define_constant("chores.rival_before", "")    -- commands before fighting a rival ($target is replaced)
ck:define_constant("chores.rival_attack", "")    -- attack to repeat on the rival (target appended)
ck:define_constant("chores.rival_after", "")     -- commands after the rival is dealt with ($target is replaced)
ck:define_constant("chores.grave_period", 5)     -- minutes between gravedigger tasks
local GRAVE_MIN_PL = 1000000000                  -- Billy's power level requirement
-- How to get to Gravedigger Billy. May include the 'pursue gravedigger' step
-- itself; if it does not, the bot adds it.
ck:define_constant("chores.grave_path", "focus 'instant' gine;pursue gravedigger")
-- Movement commands from Billy to each plot
local grave_plots = {
    "w;w;w;w;w;s",
    "w;w;w;s",
    "w;w;w;w;w;n;w;n",
    "w;w;w;w;n;n",
    "w;w;n;n",
    "w;n;n;n;w;w;w;w;w;n",
    "w;n;n;n;w;w;w;n",
}
for plot, route in ipairs(grave_plots) do
    ck:define_constant(f "chores.grave_plot_{plot}", route)
end

ck:define_feature("chores.debug", false)

-- Step-by-step tracing for when a cycle stalls: CH feature chores.debug on
local function trace(msg)
    if ck:feature("chores.debug") then
        cecho(f "<yellow>[ Chores debug ] {msg}\n")
    end
end

local function send_path(name)
    local path = ck:constant(name)
    if path ~= "" then
        API:send_multi(path)
    end
end

local function wants_fishing()
    return Chores.mode == "fish" or Chores.mode == "both"
end

local function wants_quest()
    return Chores.mode == "quest" or Chores.mode == "both"
end

function Chores:castout()
    self.last_cast = getEpoch()
    self.line_out = true
    send("castout")
end

-- Walk back to the fishing spot (from the quest end or the rest room) and
-- resume casting; quest-only mode walks back too, then idles there.
function Chores:return_to_fishing()
    local path = ck:constant("chores.fishing_path")
    if path ~= "" then
        API:send_multi(path)
    elseif not self.warned_no_path then
        self.warned_no_path = true
        print("[ Chores ] - set `CH constant chores.fishing_path=\"...\"` so I can walk back to the fishing spot.")
    end
    if wants_fishing() then
        self.activity = "fishing"
        self:castout()
    else
        self.activity = "idle"
    end
end

-- Fishing triggers ---------------------------------------------------------

function Chores:tug()
    -- Reelin always lands the fish; recast right away when the bot is on
    send("reelin")
    self.line_out = false
    if self.activity == "fishing" then
        self.bad_spots = nil -- a bite proves the spot is fine
        self:castout()
    end
end

-- 'This is not a good place to fish, find a better spot.' - we drifted off
-- the fishing spot somehow; walk the fishing path back and try again. Three
-- strikes without a bite in between means the path itself is wrong: stop.
function Chores:bad_spot()
    if self.activity ~= "fishing" then
        return
    end
    self.bad_spots = (self.bad_spots or 0) + 1
    if self.bad_spots >= 3 then
        print("[ Chores ] - still not a good fishing spot after walking back; check `chores.fishing_path`. Stopping.")
        self.activity = "idle" -- no line out, nothing to reel
        self:stop()
        return
    end
    print("[ Chores ] - bad fishing spot, walking back")
    self:return_to_fishing()
end

function Chores:another_tug()
    -- Multi-catch: the line is still out with the next fish, reel only
    send("reelin")
    self.line_out = false
    if self.activity == "fishing" then
        self.last_cast = getEpoch()
    end
end

-- 'You aren't even fishing!' / 'You reel in your line, but nothing was caught
-- this time.' - there is no line in the water. Cast again, unless tug() has
-- already put a fresh one out.
function Chores:line_empty()
    if self.activity ~= "fishing" or self.line_out then
        return
    end
    self:castout()
end

function Chores:tangle()
    if self.activity == "fishing" then
        self:castout()
    end
end

-- Head for the rest room and sleep. no_reel skips pulling the line in, for
-- the cases where the cast never landed in the water.
function Chores:go_rest(no_reel)
    self.activity = "resting"
    if not no_reel then
        send("reelin") -- pull the line in before leaving
    end
    send_path("chores.rest_path")
    send("land") -- can't sleep while flying
    send("sleep")
end

-- 'You are too exhausted to fish right now.' - the mud's own verdict, which
-- beats waiting for the fatigue percentage to cross our threshold
function Chores:too_exhausted()
    if self.activity ~= "fishing" then
        return
    end
    print("[ Chores ] - too exhausted to fish, going to rest")
    self:go_rest(true) -- the cast was refused, so no line is out
end

-- Quest cycle --------------------------------------------------------------

function Chores:start_quest()
    if self.activity == "resting" then
        send("wake") -- the delivery outranks a nap
    elseif self.activity == "fishing" then
        send("reelin") -- pull the line in before leaving
    end
    self.activity = "quest"
    local path = ck:constant("chores.cook_path")
    if path:find("pursue", 1, true) then
        -- The path goes all the way to the cook; wait for him to speak
        self.quest = { step = "cook", tries = 1, deadline = getEpoch() + 20 }
    else
        self.quest = { step = "roshi", tries = 1, deadline = getEpoch() + 10 }
    end
    trace("quest: travelling to the cook")
    API:send_multi(path)
end

function Chores:roshi_seen()
    local q = self.quest
    if self.activity ~= "quest" or q.step ~= "roshi" then
        return
    end
    q.step = "cook"
    q.deadline = getEpoch() + 15
    send("pursue royal cook")
end

function Chores:cook_asked()
    local q = self.quest
    if self.activity ~= "quest" or q.step ~= "cook" then
        return
    end
    q.step = "name"
    q.deadline = getEpoch() + 15
    send("say yes")
end

function Chores:deliver_to(knight)
    send(f "pursue {knight}")
    send(f "give jerky {knight}")
    self:quest_done(f "rations delivered to {knight}", ck:constant("chores.quest_period") * 60)
end

function Chores:knight_named(name)
    local q = self.quest
    if self.activity ~= "quest" or q.step ~= "name" then
        return
    end
    self:deliver_to(name:lower())
end

function Chores:knight_reminded(name)
    -- 'What are you still doing here! I asked you to deliver the jerky to
    -- Knight Glenn!' - the delivery was already accepted (e.g. before a
    -- rival interrupted); take the jerky straight to the knight
    if self.activity ~= "quest" then
        return
    end
    self:deliver_to(name:lower())
end

function Chores:quest_cooldown(minutes)
    if self.activity ~= "quest" then
        return
    end
    -- The cook tells us how long ago the last delivery was; retry when the
    -- period is actually up instead of waiting a whole extra cycle
    local wait = math.max(ck:constant("chores.quest_period") * 60 - minutes * 60, 30)
    self:quest_done(f "cook is on cooldown, retrying in {wait}s", wait)
end

function Chores:quest_cooldown_left(n, unit)
    if self.activity ~= "quest" then
        return
    end
    -- The cook tells us exactly how long is left ('Come back in 11 seconds.')
    local wait = n * (unit:starts("minute") and 60 or 1) + 5
    self:quest_done(f "cook is on cooldown, retrying in {wait}s", wait)
end

function Chores:quest_done(why, wait)
    print(f "[ Chores ] - quest: {why}")
    self.next_quest = getEpoch() + wait
    self:return_to_fishing()
end

function Chores:quest_fail(reason)
    print(f "[ Chores ] - quest aborted: {reason}")
    self.next_quest = getEpoch() + ck:constant("chores.quest_period") * 60
    self:return_to_fishing()
end

-- Gravedigger task: reach Billy's planet, ask for a task, walk to the plot
-- he names and dig it up.

function Chores:start_grave()
    -- Billy will not deal with us below a certain power level. Base PL is the
    -- measure, so damage and transformations do not sway the check.
    local pl = Player.BasePl
    if not pl or pl < GRAVE_MIN_PL then
        if not self.warned_low_pl then
            self.warned_low_pl = true
            if pl then
                -- plain concatenation: f-strings cannot see file-level locals
                print("[ Chores ] - skipping the gravedigger task: base power level " ..
                    pl .. " is under " .. GRAVE_MIN_PL .. ".")
            else
                -- The mud stopped sending BASE_PL over MSDP; the score sheet
                -- still prints it, so one `score` unblocks the task
                print("[ Chores ] - base power level unknown, type `score` once so I can read it (the gravedigger needs 1 billion).")
            end
        end
        -- Check again next period rather than every tick
        self.next_grave = getEpoch() + ck:constant("chores.grave_period") * 60
        return
    end
    local path = ck:constant("chores.grave_path")
    if path == "" then
        if not self.warned_no_grave then
            self.warned_no_grave = true
            print("[ Chores ] - set `CH constant chores.grave_path=\"...\"` (route to Gravedigger Billy's planet) to enable the excavation task.")
        end
        self.next_grave = nil -- disabled until configured and retoggled
        return
    end
    if self.activity == "resting" then
        send("wake")
    elseif self.activity == "fishing" then
        send("reelin") -- pull the line in before leaving
    end
    self.activity = "grave"
    -- 'pursue' walks us to Billy, which takes time, so 'say task' is not sent
    -- here: the tick asks once we have had a moment to arrive and keeps
    -- asking until he answers (or the travel budget runs out).
    self.grave = { step = "travel", deadline = getEpoch() + 90, next_say = getEpoch() + 3 }
    trace("grave: travelling to Billy")
    API:send_multi(path)
    if not path:find("pursue", 1, true) then
        send("pursue gravedigger")
    end
end

function Chores:grave_plot(plot)
    if self.activity ~= "grave" then
        return
    end
    local path = plot >= 1 and plot <= #grave_plots and ck:constant(f "chores.grave_plot_{plot}") or ""
    if path == "" then
        print(f "[ Chores ] - no route mapped for plot {plot}, skipping this one.")
        self:grave_fail(f "plot {plot} has no route")
        return
    end
    -- Make sure we are carrying a shovel before trekking out to the plot;
    -- the reply (or the lack of one) decides whether we buy from Billy first
    trace(f "grave: assigned plot {plot}, checking for a shovel")
    self.grave.plot = plot
    self.grave.step = "shovel"
    self.grave.deadline = getEpoch() + 10
    send("locate shovel")
end

-- 'I already done told you! I need you to go dig up burial plot 5!' - the task
-- was already assigned (a repeated ask, or a run interrupted by a fight).
-- Treat it as the assignment unless we are already working on that plot.
function Chores:grave_reminded(plot)
    if self.activity ~= "grave" then
        return
    end
    local g = self.grave
    if g.plot == plot and g.step ~= "travel" then
        return -- already on it
    end
    trace(f "grave: Billy re-assigned plot {plot}")
    self:grave_plot(plot)
end

-- 'a wrought iron burial shovel' in the locate output: we have one. The
-- listing repeats per shovel, but grave_dig moves the step on so the extra
-- lines are ignored.
function Chores:shovel_found()
    local g = self.grave
    if self.activity ~= "grave" or not g or g.step ~= "shovel" then
        return
    end
    self:grave_dig()
end

-- 'No matching items found in your inventory.' - generic locate failure, only
-- meaningful while we are waiting on the shovel check
function Chores:shovel_missing()
    local g = self.grave
    if self.activity ~= "grave" or not g or g.step ~= "shovel" then
        return
    end
    print("[ Chores ] - no burial shovel, buying one from Billy")
    send("buy 1")
    self:grave_dig()
end

function Chores:grave_dig()
    local g = self.grave
    local plot = g.plot
    g.step = "digging"
    trace(f "grave: walking to plot {plot} and digging")
    API:send_multi(ck:constant(f "chores.grave_plot_{plot}"))
    send("dig")
    send("get all") -- pick up whatever the plot turned up
    self:grave_done(f "excavated plot {plot}", ck:constant("chores.grave_period") * 60)
end

function Chores:grave_cooldown(n, unit)
    if self.activity ~= "grave" then
        return
    end
    -- 'Sorry chum, no burial plots need excavating. Check back in 4 minutes.'
    local wait = n * (unit:starts("minute") and 60 or 1) + 5
    self:grave_done(f "no plots ready, checking back in {wait}s", wait)
end

function Chores:grave_done(why, wait)
    print(f "[ Chores ] - grave: {why}")
    self.next_grave = getEpoch() + wait
    self:return_to_fishing()
end

function Chores:grave_fail(reason)
    print(f "[ Chores ] - grave task aborted: {reason}")
    self.next_grave = getEpoch() + ck:constant("chores.grave_period") * 60
    self:return_to_fishing()
end

-- Boss fish: 'A massive shadow emerges from the depths... Prepare for
-- battle!' - fight until the MSDP opponent feed clears, then resume casting.

function Chores:boss_appeared()
    if self.mode == "off" or self.activity == "boss" then
        return
    end
    if ck:constant("chores.boss_attack") == "" then
        print("[ Chores ] - a boss fish attacked! Set `CH constant chores.boss_attack=\"<attack>\"` to fight back automatically.")
        return
    end
    self.boss = { engaged = false, deadline = getEpoch() + 20 }
    self.activity = "boss"
    send_path("chores.boss_before")
end

function Chores:boss_dead()
    if self.activity ~= "boss" then
        return
    end
    self.boss = nil
    send_path("chores.boss_after")
    -- The boss hooked at the fishing spot, no need to walk anywhere
    if wants_fishing() then
        self.activity = "fishing"
        self:castout()
    else
        self.activity = "idle"
    end
end

-- Rivals: '<Name> ... flies out of nowhere and attacks you!' while walking
-- somewhere. Fight back, then resume whatever was interrupted.

function Chores:rival_attacked(name)
    if self.mode == "off" or self.activity == "rival" then
        return
    end
    local attack = ck:constant("chores.rival_attack")
    if attack == "" then
        print("[ Chores ] - a rival attacked! Set `CH constant chores.rival_attack=\"<attack>\"` to fight back automatically.")
        return
    end
    local target = name:lower()
    self.rival = {
        target = target,
        resume = self.activity, -- what we were doing when jumped
        engaged = false,
        deadline = getEpoch() + 20,
    }
    self.activity = "rival"
    local before = ck:constant("chores.rival_before")
    if before ~= "" then
        API:send_multi((before:gsub("%$target", target)))
    end
    send(f "{attack} {target}")
end

function Chores:rival_over()
    local r = self.rival or {}
    self.rival = nil
    local after = ck:constant("chores.rival_after")
    if after ~= "" then
        API:send_multi((after:gsub("%$target", r.target or "")))
    end
    if r.resume == "quest" then
        -- We are already on Earth for the delivery: go straight back to the
        -- cook. He either re-asks (fresh quest) or reminds us which knight
        -- the jerky is for (delivery already accepted) - both are handled.
        self.activity = "quest"
        self.quest = { step = "cook", deadline = getEpoch() + 15 }
        send("pursue royal cook")
    elseif r.resume == "grave" then
        -- Restart the excavation from the top: its path starts from anywhere
        self.activity = "idle"
        self:start_grave()
    else
        -- Resuming via the fishing path also covers an interrupted rest:
        -- the fatigue check sends us right back to bed on the next tick
        self:return_to_fishing()
    end
end

-- '<Name> is dead!  R.I.P.' - the authoritative end of a fight. The MSDP
-- opponent feed does not always clear after a kill, so waiting for it can
-- leave the bot stuck mid-fight; the death line settles it. The MSDP check
-- stays as a backup for fights that end without a kill (a rival fleeing).
function Chores:something_died()
    Target.name = ""
    if self.activity == "boss" then
        self:boss_dead()
    elseif self.activity == "rival" then
        self:rival_over()
    end
end

-- Death: 'You are dead!  You are sent to the Next Dimension.' - abandon any
-- fight or quest and head back to fishing. The dead-room line ('such a
-- peaceful, easy feeling...') appears for every command sent while dead, so
-- recovery is debounced: one attempt, then let the fishing heartbeat retry.
function Chores:died()
    if self.mode == "off" then
        return
    end
    local now = getEpoch()
    if self.last_death and now - self.last_death < 15 then
        return
    end
    self.last_death = now
    print("[ Chores ] - we died! Heading back to the fishing spot.")
    self.rival = nil
    self.boss = nil
    if self.activity == "quest" then
        self.next_quest = now + ck:constant("chores.quest_period") * 60
    elseif self.activity == "grave" then
        self.next_grave = now + ck:constant("chores.grave_period") * 60
    end
    self:return_to_fishing()
end

-- The tick -----------------------------------------------------------------

local function do_chores()
    if not API:is_connected() then
        return
    end
    local now = getEpoch()
    local act = Chores.activity

    -- Quest scheduling preempts fishing and resting (cook before gravedigger)
    if wants_quest() and (act == "fishing" or act == "idle" or act == "resting") then
        if Chores.next_quest and now >= Chores.next_quest then
            Chores:start_quest()
            return
        elseif Chores.next_grave and now >= Chores.next_grave then
            Chores:start_grave()
            return
        end
    end

    if act == "grave" then
        local g = Chores.grave
        if g.step == "travel" and now >= (g.next_say or 0) then
            -- Keep asking until Billy answers: the pursue may still be walking
            send("say task")
            g.next_say = now + 5
        end
        if now > g.deadline then
            if g.step == "shovel" then
                -- No locate output at all; assume the worst and buy one
                Chores:shovel_missing()
            else
                Chores:grave_fail(f "timed out at step '{g.step}'")
            end
        end
    elseif act == "quest" then
        local q = Chores.quest
        if now > q.deadline then
            if q.step == "roshi" and q.tries < 3 then
                q.tries = q.tries + 1
                q.deadline = now + 10
                API:send_multi(ck:constant("chores.cook_path"))
            else
                Chores:quest_fail(f "timed out waiting at step '{q.step}'")
            end
        end
    elseif act == "fishing" then
        local fatigue_pct = (Player.Fatigue and Player.MaxFatigue)
            and (Player.Fatigue / Player.MaxFatigue * 100) or nil
        if fatigue_pct and fatigue_pct < ck:constant("chores.rest_below") then
            Chores:go_rest()
        elseif now - (Chores.last_cast or 0) > ck:constant("chores.recast_timeout") then
            -- No bite for a while: the line may be gone, cast again
            Chores:castout()
        end
    elseif act == "resting" then
        if Player.Fatigue and Player.MaxFatigue and Player.Fatigue >= Player.MaxFatigue then
            send("wake")
            Chores:return_to_fishing()
        end
    elseif act == "boss" then
        local b = Chores.boss
        local fighting = Target.name ~= nil and Target.name ~= ""
        if fighting then
            b.engaged = true
        end
        if b.engaged and not fighting then
            -- Opponent gone from the MSDP feed: boss is dead
            Chores:boss_dead()
        elseif not b.engaged and now > b.deadline then
            -- Never saw the fight start; assume it resolved on its own
            Chores:boss_dead()
        else
            send(ck:constant("chores.boss_attack"))
        end
    elseif act == "rival" then
        local r = Chores.rival
        local fighting = Target.name ~= nil and Target.name ~= ""
        if fighting then
            r.engaged = true
        end
        if r.engaged and not fighting then
            -- Opponent gone from the MSDP feed: fight is over
            Chores:rival_over()
        elseif not r.engaged and now > r.deadline then
            -- Never saw the fight start; assume it resolved on its own
            Chores:rival_over()
        else
            local attack = ck:constant("chores.rival_attack")
            send(f "{attack} {r.target}")
        end
    end
end

-- Control ------------------------------------------------------------------

function Chores:stop()
    deleteNamedTimer("__PKGNAME__", "CH:Chores")
    if self.activity == "fishing" then
        send("reelin") -- pull the line in before stopping
    end
    self.mode = "off"
    self.activity = "idle"
    print("[ Chores ] - off")
end

function Chores:toggle(mode)
    if mode == nil then
        -- bare 'chores' flips between off and both
        if self.mode ~= "off" then
            self:stop()
        else
            self:toggle("both")
        end
        return
    end
    if mode == "off" then
        if self.mode ~= "off" then
            self:stop()
        else
            print("chores is off - 'chores' (both) or 'chores <fish|quest|both>' to start")
        end
        return
    end
    if self.mode ~= "off" then
        self:stop()
    end
    self.mode = mode
    self.warned_no_path = nil
    self.warned_no_grave = nil
    self.warned_low_pl = nil
    self.bad_spots = nil
    self.quest = {}
    self.next_quest = nil
    -- The gravedigger runs on the first tick after the cook delivery is done
    self.next_grave = wants_quest() and getEpoch() or nil
    print(f "[ Chores ] - mode: {mode}")
    registerNamedTimer("__PKGNAME__", "CH:Chores", 2, do_chores, true)
    if wants_quest() then
        -- Delivery first; finishing it drops us into the main loop (fishing)
        self:start_quest()
    elseif wants_fishing() then
        self.activity = "fishing"
        self:castout()
    else
        self.activity = "idle"
    end
end