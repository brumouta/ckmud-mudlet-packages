local ck = require("__PKGNAME__")
local Player = ck:get_table("Player")
local Toggles = ck:get_table("Toggles")
local learn = ck:get_table("API.Learning", {
    triggers = {},
    gravity = 0,
    to_learn = {}
})
local Times = ck:get_table("API.Times")
local API = ck:get_table("API")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")
local PromptCounters = ck:get_table("PromptCounters")
local Skills = ck:get_table("API.Skills")
local Room = ck:get_table("Room")
local Target = ck:get_table("Target")

ck:define_feature("learning.use_zeta", false)
ck:define_constant("learning.return_to_target", "")
ck:define_constant("learning.recall_isolation", "")

-- The way back to the target, worked out from the path you start with: learning.recall_isolation takes you
-- to the isolation tank, then the path backwards gets you to the target. Steps that undo each other cancel:
-- recall_isolation "crecall;w" + `autolearn elder n;n;n;n;w` -> crecall;w;e;s;s;s;s -> "crecall;s;s;s;s"
local OPPOSITE = { n = "s", s = "n", e = "w", w = "e", u = "d", d = "u",
    ne = "sw", sw = "ne", nw = "se", se = "nw", ["in"] = "out", out = "in" }
local LONG = { north = "n", south = "s", east = "e", west = "w", up = "u", down = "d",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw" }

-- "n;;n;;n;;n;;w", "n;n;n;n;w", "n n n n w", "4n w", "n,n,w" -> { "n", "n", "n", "n", "w" }
-- nil if a step isn't a direction (e.g. "enter vortex"): that can't be walked backwards.
function learn.parse_path(path)
    local dirs = {}
    for token in (path or ""):lower():gmatch("[^;,%s]+") do
        local count, dir = token:match("^(%d*)(%a+)$")
        dir = dir and (LONG[dir] or dir)
        if not dir or not OPPOSITE[dir] then return nil end
        for _ = 1, tonumber(count) or 1 do dirs[#dirs + 1] = dir end
    end
    if #dirs == 0 then return nil end
    return dirs
end

-- The command that starts the walk back: the first one of learning.recall_isolation (crecall, recall...)
function learn.recall_command()
    local iso = ck:constant("learning.recall_isolation") or ""
    return iso:match("^%s*([^;%s][^;]*)")
end

-- Only with learning.recall_isolation set: without it the path is the old speedwalk to the rest spot.
function learn.return_from(path)
    if not learn.recall_command() then return nil end
    local dirs = learn.parse_path(path)
    if not dirs then return nil end
    local back = {}
    for cmd in (ck:constant("learning.recall_isolation") or ""):gmatch("[^;]+") do
        cmd = cmd:match("^%s*(.-)%s*$")
        if cmd ~= "" then
            -- a step that undoes the one before it cancels out (w then e); anything else stays
            local top = back[#back]
            if top and OPPOSITE[top] == cmd then back[#back] = nil else back[#back + 1] = cmd end
        end
    end
    for i = #dirs, 1, -1 do
        local step, top = OPPOSITE[dirs[i]], back[#back]
        if top and OPPOSITE[top] == step and #back > 1 then back[#back] = nil else back[#back + 1] = step end
    end
    return table.concat(back, ";")
end

-- The path back to the target: from the path you started with, else the constant
function learn:return_path()
    return self.derived_return or ck:constant("learning.return_to_target") or ""
end

local function aoe_ok()
    return API:status_ok()
end

local function heal_ok()
    return API:status_ok()
end

local function buff_ok()
    return API:status_ok()
end

local function ultra_ok(skill)
    return Player.GK >= ((500 * (100 - (Skills:level(skill) or 1)) / 100) + 5)
end

-- The first skill in the list we have enough ki / fatigue / god ki for, using the
-- costs in the attack table. Lets a cheaper skill train while an expensive one waits.
local function first_affordable(list, can_use)
    for _, name in ipairs(list) do
        if can_use(name) then return name end
    end
end

local function can_use_energy(name) return API:can_use_energy_attack(name) end
local function can_use_melee(name) return API:can_use_melee_attack(name) end
local function can_use_any(name) return API:can_use_attack(name) end

---@diagnostic disable-next-line: unused-function
local function do_learning()
    if not API:is_connected() then
        -- Don't do anything unless we are connected and have a prompt
        return
    end
    local speedwalk_path = learn.speedwalk

    if State:is(State.NORMAL) and API:cmd_stack_empty() then
        local target = AL.table.sample_items(learn.target:split(","))
        local sent = false
        local to_learn = learn.to_learn
        if next(learn.gk_blocked) and Player.GK and Player.MaxGK and Player.GK >= Player.MaxGK then
            learn.gk_blocked = {}                   -- god ki is full again: try those skills again
        end
        local learned = learn:setup_skills(target)
        learn:maybe_adjust_gravity()

        -- The first command sent below is this tick's skill attempt. If the MUD answers
        -- "You lack sufficient god ki...", that's the skill to set aside (out_of_god_ki).
        learn.attempt = nil
        local function send(cmd, ...)
            if learn.attempt == nil then learn.attempt = cmd end
            return _G.send(cmd, ...)
        end

        -- Handle Primary Skills
        -- Ki attacks first, then fatigue ones: when ki runs low the melee skills keep
        -- training (and the other way round). Resting only happens once nothing fits.
        local energy = first_affordable(to_learn.energy, can_use_energy)
        local melee = first_affordable(to_learn.melee, can_use_melee)
        local ultra = first_affordable(to_learn.ultras, ultra_ok)
        local learnable = first_affordable(to_learn.learnable, can_use_any)
        if energy then
            send(f "{energy} {target}")
            sent = true
        elseif melee then
            send(f "{melee} {target}")
            sent = true
        elseif #(to_learn.aoe) > 0 and aoe_ok() then
            send(f "{to_learn.aoe[1]}")
            sent = true
        elseif #(to_learn.buffs) > 0 and buff_ok() then
            send(f "focus '{to_learn.buffs[1]}'")
            sent = true
        elseif #(to_learn.heals) > 0 and heal_ok() then
            send(f "focus '{to_learn.heals[1]}'")
            sent = true
        elseif ultra then
            send(f "focus '{ultra}'")
            send("urevert")
            sent = true
        elseif learnable then
            send(f "{learnable} {target}")
            sent = true
        elseif learn:need_to_master("powersense") and API:status_ok() then
            send(f "powersense {target}")
            sent = true
        elseif (learn:need_to_master("powerdown") or learn:need_to_master("powerup")) and API:status_ok() then
            send("powerdown")
            send("powerup")
            sent = true
        elseif learn:need_to_master("sup") and API:status_ok() then
            send("sup 69")
            send("sup")
            sent = true
        elseif learn:need_to_master("battlerespite") and Player.Ki > 500 then
            send("focus 'battle respite'")
            send("stand")
            sent = true
        elseif learn:need_to_master("purification") and Player.Ki > 250 then
            send("focus 'purification'")
            sent = true
        elseif learn:need_to_master("ironwill") and Player.Ki > 250 then
            send("focus 'iron will'")
            sent = true
        elseif target ~= "self" and learn:need_to_master("unravel defense") and API:status_ok() then
            send(f "focus 'unravel' {target}")
            sent = true
        elseif learn:need_to_master("scan") and API:status_ok() then
            send("scan")
            sent = true
        elseif learn:need_to_master("taiyoken") and Player.Ki > API:get_energy_cost("taiyoken", 10) then
            send(f"focus 'taiyoken' {target}")
            sent = true
        elseif learn:need_to_master("portal") and Player.Ki > (Player.MaxKi * .10) and learn:can_return() then
            send(f "focus 'portal' king kai")
            learn.teleported = true
            sent = true
        elseif learn:need_to_master("instant") and Player.Ki > 500 and learn:can_return() then
            send(f "focus 'instant' king kai")
            learn.teleported = true
            sent = true
        elseif target ~= "self" and Skills:mastered("kick") and Player.LBS < 100 and API:can_use_melee_attack("kick") then
            send(f "kick {target}")
            sent = true
        elseif target ~= "self" and Skills:mastered("punch") and Player.UBS < 100 and API:can_use_melee_attack("punch") then
            send(f "punch {target}")
            sent = true
        end

        if sent == false and learn.teleported then
            -- We teleported away to train portal/instant; walk back to the
            -- target before deciding anything else - resting from the wrong
            -- room would speedwalk the isolation path from king kai
            learn:return_home()
            return
        end

        if sent == false and not API:is_rested() and Target.level == 0 then
            learn:go_rest(speedwalk_path)
            return
        end

        local others = { "powersense", "powerup", "powerdown", "portal", "instant", "scan" }
        if sent == false and learned == 0 and Player.UBS == 100 and Player.LBS == 100 then
            -- check others
            local all_done = true
            for _, v in ipairs(others) do
                if learn:need_to_master(v) then
                    all_done = false
                end
            end
            if all_done then
                -- Lets turn on zeta on the target
            end
        end

        -- If we didn't do anything we are probably done.
    elseif State:is(State.REST) then
        -- WE are resting
        -- If we are a android do nothing, the triggers will take us out of rest
        if not API:isAndroid() and API:is_rested() then
            if learn:use_recall_rest() then
                State:set(State.NORMAL)
                send("wake")
                API:send_multi(learn:return_path())
            elseif speedwalk_path then
                State:set(State.SPEEDWALK)
                send("wake")

                registerAnonymousEventHandler("sysSpeedwalkFinished", function()
                    State:set(State.NORMAL)
                end, true)
                speedwalk(speedwalk_path, true, 0.5)
            end
        end
    end
end

local function exit()
    -- Delete timer
    deleteNamedTimer("__PKGNAME__", "AL:Learning")
    -- Kill Triggers
    for _, id in ipairs(learn.triggers) do
        killTrigger(id)
    end
    learn.triggers = {}
    disableTrigger("autolearn no target")
end

local function enter()
    send("learn")
    -- Change Mode
    Mode:switch(Mode.Learning, exit)
    -- Clear out all state
    learn.state = {}
    learn.to_learn = {
        set = false
    }
    learn.gravity = 0
    learn.warned_no_return = nil
    learn.teleported = nil
    -- Always armed: find_target no-ops while return_to_target is unset, and
    -- this keeps the return flow working if the constant is set mid-session.
    enableTrigger("autolearn no target")

    -- Install a timer
    registerNamedTimer("__PKGNAME__", "AL:Learning", 2, do_learning, true)
end

function learn:return_home()
    -- Walk back to the training target and forget any pending teleport
    self.teleported = nil
    local path = self:return_path()
    if path ~= "" then
        API:send_multi(path)
    end
end

-- Go and rest: androids vent and repair; otherwise recall to the isolation tank, or
-- speedwalk the rest path. Getting back up happens in the REST state once
-- API:is_rested() (PL, ki, fatigue and god ki all full).
function learn:go_rest(speedwalk_path)
    if API:isAndroid() then
        State:set(State.REST)
        send("vent")
        send("repair")
    elseif learn:use_recall_rest() then
        -- Recall-based path works from any room, unlike the
        -- reversible speedwalk which assumes we stand at the target
        State:set(State.REST)
        API:send_multi(ck:constant("learning.recall_isolation"))
        send("sleep")
    elseif speedwalk_path then
        State:set(State.SPEEDWALK)

        registerAnonymousEventHandler("sysSpeedwalkFinished", function()
            State:set(State.REST)
            send("sleep")
        end, true)
        speedwalk(speedwalk_path, false, 0.5)
    end
end

-- Skills set aside because they need more god ki than we have: { ultrainstinct = true, ... }.
-- Cleared once god ki is full (e.g. after resting). Names compare without spaces, so
-- "iron will", "ironwill" and focus 'iron will' are the same skill.
learn.gk_blocked = learn.gk_blocked or {}
local function skill_key(name)
    return (name or ""):lower():gsub("%s", "")
end

-- The skill a command trains: focus 'ultra instinct' -> ultra instinct, "hakai troll" -> hakai
local function skill_of(command)
    return command:match("^%s*focus%s+'([^']+)'") or command:match("^%s*(%S+)")
end

function learn:gk_blocked_skill(name)
    return self.gk_blocked[skill_key(name)] == true
end

-- Trigger: "You lack sufficient god ki to use that technique!" (only while the bot runs).
-- Set that skill aside and keep training ones that use ki or fatigue; the bot rests by
-- itself once nothing else can be done (resting refills all three), then tries it again.
function learn:out_of_god_ki()
    if not Mode:is(Mode.Learning) or not learn.attempt then
        return
    end
    local skill = skill_of(learn.attempt)
    if skill and not learn:gk_blocked_skill(skill) then
        learn.gk_blocked[skill_key(skill)] = true
        cecho(f "\n<yellow>[ Autolearn ] - Not enough god ki for {skill}: training other skills first, " ..
            "then resting until god ki is full.\n")
    end
end

function learn:use_recall_rest()
    -- Rest by recalling to an isolation tank: learning.recall_isolation gets
    -- there from any room, learning.return_to_target gets back afterwards.
    -- Both are needed, since a recall path cannot be walked in reverse.
    return ck:constant("learning.recall_isolation") ~= "" and learn:return_path() ~= ""
end

function learn:can_return()
    -- Portal/instant training teleports the character to king kai; the way
    -- back is the 'autolearn no target' trigger sending return_to_target.
    -- Only attempt those skills when that path is configured, otherwise the
    -- character ends up stranded in a room with no mobs.
    local ok = self:return_path() ~= ""
    if not ok and not self.warned_no_return then
        self.warned_no_return = true
        cecho("<yellow>[ Autolearn ] - Skipping portal/instant training: they teleport you to king kai." ..
            " Start with the path to your rest spot (autolearn <target> n;n;w) so it can walk back.\n")
    end
    return ok
end

-- Skills the MUD added after our attack table was written (thunderclap was one) have
-- no cost data, so the bot could never afford them and would stop training that whole
-- list. Leave them out, and say once which ones need adding to Attacks.lua.
learn.unknown_warned = learn.unknown_warned or {}
function learn:known_attacks(list)
    local known = {}
    for _, name in ipairs(list) do
        if Player.Attacks[name] then
            table.insert(known, name)
        elseif not self.unknown_warned[name] then
            self.unknown_warned[name] = true
            cecho(f "\n<yellow>[ Autolearn ] - Skipping {name}: Autolearn doesn't know this attack yet (its cost and damage). " ..
                "Send its `help {name}` to have it added.\n")
        end
    end
    return known
end

function learn:find_target(ability)
    if not Mode:is(Mode.Learning) then
        disableTrigger("autolearn no target")
        return
    end
    if State:is(State.NORMAL) and self:return_path() ~= "" then
        self:return_home()
    end
end

-- "Maybe you should land first!": the bot tried something that can't be done while
-- flying. Land; the next tick tries it again. Only while the bot runs, so a command
-- you typed yourself doesn't make you land.
function learn:land()
    if Mode:is(Mode.Learning) then
        send("land")
    end
end

function learn:maybe_adjust_gravity()
    local new_grav = API:get_gravity()
    if Room.Gravity < new_grav and ck:feature("learning.use_zeta") then
        send(f "adjust {new_grav}")
    end
end

function learn:setup_skills(target)
    local to_learn = self.to_learn
    -- figure out what we should learn
    -- Clean slate
    ck:clear_table(to_learn)
    to_learn.set = true

    if target ~= "self" then
        to_learn.energy = learn:known_attacks(Skills:filter_mastered(Skills:energy_attacks()))
        to_learn.melee = learn:known_attacks(Skills:filter_mastered(Skills:melee_attacks()))
        to_learn.aoe = Skills:filter_mastered(Skills:AoE())
        to_learn.learnable = learn:known_attacks(Skills:learnable())
    else
        to_learn.energy = {}
        to_learn.melee = {}
        to_learn.aoe = {}
        to_learn.learnable = {}
    end
    to_learn.buffs = Skills:filter_mastered(Skills:buffs())
    to_learn.heals = Skills:filter_mastered(Skills:heals())
    to_learn.ultras = Skills:filter_mastered(Skills:ultras())
    for _, kind in ipairs({ "energy", "melee", "aoe", "learnable", "buffs", "heals", "ultras" }) do
        local kept = {}
        for _, name in ipairs(to_learn[kind]) do
            if not learn:gk_blocked_skill(name) then table.insert(kept, name) end
        end
        to_learn[kind] = kept
    end
    return self:count_to_learn()
end

function learn:need_to_master(name)
    -- If its learned and not mastered (and not set aside for lack of god ki)
    return Skills:learned(name) and not Skills:mastered(name) and not learn:gk_blocked_skill(name)
end

function learn:count_to_learn()
    local to_learn = self.to_learn
    if to_learn.set then
        return (#(to_learn.energy) + #(to_learn.melee) + #(to_learn.aoe) + #(to_learn.buffs) + #(to_learn.heals) +
            #(to_learn.ultras) + #(to_learn.learnable))
    end
    return -1
end

function learn:toggle(target, path)
    self.target = target
    self.speedwalk = path
    if not Mode:is(Mode.Learning) then
        self.derived_return = path and learn.return_from(path) or nil
        if path and not self.derived_return and learn.recall_command() then
            cecho("<yellow>[ Autolearn ] - Can't walk '" .. path .. "' backwards (only directions can be): " ..
                "using learning.return_to_target to get back.\n")
        end
    end
    if Mode:is(Mode.Learning) then
        Mode:switch(Mode.Interactive)
        print("Learning Mode Disabled!!!")
    else -- Its off
        local is_android = API:isAndroid()
        if target == nil or (path == nil and not is_android and not self:use_recall_rest()) then
            if is_android then
                print("Learning mode requires a target argument!")
            else
                print("Learning mode requires target and a speedwalk to rest" ..
                    " (or set learning.recall_isolation and learning.return_to_target)")
            end
        else
            print("Learning Mode Enabled!!!")
            if self:return_path() ~= "" then
                print("Way back to the target: " .. self:return_path())
            end
            -- Change Mode
            enter()
        end
    end
end
