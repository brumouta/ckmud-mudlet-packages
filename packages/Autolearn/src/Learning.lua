local ck = AL.ck
local Player = ck:get_table("Player")
local Toggles = ck:get_table("Toggles")
local learn = ck:get_table("API.Learning", {
    triggers = {},
    to_learn = {}
})
local Times = ck:get_table("API.Times")
local API = ck:get_table("API")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")
local PromptCounters = ck:get_table("PromptCounters")
local Skills = ck:get_table("API.Skills")
local Target = ck:get_table("Target")

-- (learning.return_to_target is gone: the way back comes from the path autolearn is started with)
ck:define_constant("learning.recall_isolation", "")
-- Skills to train first, in order: "multiform, rescue, kamehameha" (empty: the usual order)
ck:define_constant("learning.priority", "")

-- The way back to the target, worked out from the path you start with (target -> rest spot):
-- first get to the rest spot, then walk the path backwards with every step reversed. With
-- learning.recall_isolation set (al recall crecall;w) that's the recall itself:
-- `al path n;n;n;n;w` -> "crecall;w;e;s;s;s;s". Without it, plain crecall: "crecall;e;s;s;s;s".
local RECALL = "crecall"
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

function learn.return_from(path, recall)
    local dirs = learn.parse_path(path)
    if not dirs then return nil end
    if recall == nil then recall = ck:constant("learning.recall_isolation") end
    recall = (recall or ""):gsub("^[%s;]+", ""):gsub("[%s;]+$", "")
    local back = { recall ~= "" and recall or RECALL }
    for i = #dirs, 1, -1 do back[#back + 1] = OPPOSITE[dirs[i]] end
    return table.concat(back, ";")
end

-- The path back to the target, from the path autolearn was started with ("" when there's none).
-- Worked out each time, so a recall set while learning counts straight away.
function learn:return_path()
    if not self.derived_return then return "" end
    return learn.return_from(self.speedwalk) or ""
end

local function skill_key(name)
    return (name or ""):lower():gsub("%s", "")
end

local function status_ok()
    return API:status_ok()
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
        local to_learn = learn.to_learn
        if next(learn.gk_blocked) and Player.GK and Player.MaxGK and Player.GK >= Player.MaxGK then
            learn.gk_blocked = {}                   -- god ki is full again: try those skills again
        end
        learn:setup_skills(target)

        -- The first command sent below is this tick's skill attempt. If the MUD answers
        -- "You lack sufficient god ki...", that's the skill to set aside (out_of_god_ki).
        learn.attempt = nil
        local function send(cmd, ...)
            if learn.attempt == nil then learn.attempt = cmd end
            return _G.send(cmd, ...)
        end

        -- Everything there is to train this tick, in the default order: ki attacks first, then
        -- fatigue ones (when ki runs low the melee skills keep training, and the other way round),
        -- then the rest. learning.priority moves the skills it names to the front. The first one
        -- we can afford right now is used; resting only happens once nothing fits.
        local sent = learn:train(learn:candidates(target, to_learn), send)

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

-- learning.priority: "multiform, rescue, kamehameha" -> { multiform = 1, rescue = 2, kame = 3 }.
-- Names as `learn` shows them or as typed (instant trans / instant, iron will / ironwill).
function learn.priority_rank()
    local rank, n = {}, 0
    for raw in (ck:constant("learning.priority") or ""):gmatch("[^,;]+") do
        local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            local key = skill_key(Skills:translate(name))
            if not rank[key] then
                n = n + 1
                rank[key] = n
            end
        end
    end
    return rank
end

local function distance(a, b)
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[#b]
end

-- Check the learning.priority names against your skills (from `learn`). Returns nil when
-- the skills aren't known yet, else a list of { name = typed, suggestion = closest or nil }.
-- Spaces don't matter (power up = powerup).
function learn.check_priority(list)
    local Learned = ck:get_table("Player.Skills").Learned or {}
    if not next(Learned) then return nil end
    local keys = {}
    for skill in pairs(Learned) do keys[skill_key(skill)] = skill end
    local unknown = {}
    for raw in (list or ""):gmatch("[^,;]+") do
        local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local key = skill_key(Skills:translate(name))
        if name ~= "" and not keys[key] and not keys[skill_key(name)] then
            local best, best_d
            for k, skill in pairs(keys) do
                local d = distance(key, k)
                if not best_d or d < best_d or (d == best_d and skill < best) then best, best_d = skill, d end
            end
            unknown[#unknown + 1] = { name = name, suggestion = best_d and best_d <= math.max(2, math.floor(#key / 4)) and best or nil }
        end
    end
    return unknown
end

local function affordable_ki(cost)
    return function() return Player.Ki > cost end
end

-- Each candidate: { skill = name (for learning.priority), cmds = { ... }, ok = function, after = function }
function learn:candidates(target, to_learn)
    local list = {}
    local function add(skill, cmds, ok, after)
        list[#list + 1] = { skill = skill, cmds = cmds, ok = ok, after = after }
    end
    local function each(names, cmd_of, ok)
        for _, name in ipairs(names) do
            add(name, cmd_of(name), function() return ok(name) end)
        end
    end
    local on_target = function(name) return { name .. " " .. target } end
    local focus = function(name) return { "focus '" .. name .. "'" } end
    local mastering = function(name) return learn:need_to_master(name) end

    each(to_learn.energy, on_target, can_use_energy)
    each(to_learn.melee, on_target, can_use_melee)
    each(to_learn.aoe, function(name) return { name } end, aoe_ok)
    each(to_learn.buffs, focus, buff_ok)
    each(to_learn.heals, focus, heal_ok)
    each(to_learn.ultras, function(name) return { "focus '" .. name .. "'", "urevert" } end, ultra_ok)
    each(to_learn.learnable, on_target, can_use_any)

    if mastering("powersense") then add("powersense", { "powersense " .. target }, status_ok) end
    if mastering("powerdown") or mastering("powerup") then
        add(mastering("powerdown") and "powerdown" or "powerup", { "powerdown", "powerup" }, status_ok)
    end
    if mastering("sup") then add("sup", { "sup 69", "sup" }, status_ok) end
    if mastering("battlerespite") then
        add("battlerespite", { "focus 'battle respite'", "stand" }, affordable_ki(500))
    end
    if mastering("purification") then add("purification", { "focus 'purification'" }, affordable_ki(250)) end
    if mastering("iron will") then add("iron will", { "focus 'iron will'" }, affordable_ki(250)) end
    -- Multiform makes a clone (10 ki, 3 at most); dismiss it right away so there's always room
    -- for the next one and no clone wanders after you.
    if mastering("multiform") then
        add("multiform", { "focus 'multiform'", "order followers dismiss" }, function()
            return API:status_ok() and Player.Ki > API:get_energy_cost("multiform", 10)
        end)
    end
    if target ~= "self" and mastering("unravel defense") then
        add("unravel defense", { "focus 'unravel' " .. target }, status_ok)
    end
    if mastering("scan") then add("scan", { "scan" }, status_ok) end
    if mastering("taiyoken") then
        add("taiyoken", { "focus 'taiyoken' " .. target }, function()
            return Player.Ki > API:get_energy_cost("taiyoken", 10)
        end)
    end
    local teleported = function() learn.teleported = true end
    if mastering("portal") then
        add("portal", { "focus 'portal' king kai" }, function()
            return Player.Ki > (Player.MaxKi * .10) and learn:can_return()
        end, teleported)
    end
    if mastering("instant") then
        add("instant", { "focus 'instant' king kai" }, function()
            return Player.Ki > 500 and learn:can_return()
        end, teleported)
    end

    -- learning.priority first (in its order), everything else keeps its place
    local rank = learn.priority_rank()
    if next(rank) then
        for i, c in ipairs(list) do c.index = i end
        local last = #list + 1
        table.sort(list, function(a, b)
            local ra, rb = rank[skill_key(a.skill)] or last, rank[skill_key(b.skill)] or last
            if ra ~= rb then return ra < rb end
            return a.index < b.index
        end)
    end

    -- Not training a skill: keep body stats up with kick/punch once nothing else fits
    if target ~= "self" then
        add(nil, { "kick " .. target }, function()
            return Skills:mastered("kick") and Player.LBS < 100 and API:can_use_melee_attack("kick")
        end)
        add(nil, { "punch " .. target }, function()
            return Skills:mastered("punch") and Player.UBS < 100 and API:can_use_melee_attack("punch")
        end)
    end
    return list
end

-- Send the first candidate we can afford; true if something was sent
function learn:train(list, send)
    for _, c in ipairs(list) do
        if c.ok() then
            for _, cmd in ipairs(c.cmds) do send(cmd) end
            if c.after then c.after() end
            return true
        end
    end
    return false
end

local function exit()
    -- Delete timer
    deleteNamedTimer("Autolearn", "AL:Learning")
    -- Kill Triggers
    for _, id in ipairs(learn.triggers) do
        killTrigger(id)
    end
    learn.triggers = {}
    learn.watch_no_target = false
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
    learn.warned_no_return = nil
    learn.teleported = nil
    -- Always armed: find_target no-ops while there's no way back, and
    -- this keeps the return flow working if the constant is set mid-session.
    learn.watch_no_target = true

    -- Install a timer
    registerNamedTimer("Autolearn", "AL:Learning", 2, do_learning, true)
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
    -- there from any room, the way back (from the start path) gets back afterwards.
    -- Both are needed, since a recall path cannot be walked in reverse.
    return ck:constant("learning.recall_isolation") ~= "" and learn:return_path() ~= ""
end

function learn:can_return()
    -- Portal/instant training teleports the character to king kai; the way
    -- back is the 'autolearn no target' trigger walking the way back.
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
        learn.watch_no_target = false
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
        if path and not self.derived_return then
            cecho("<yellow>[ Autolearn ] - Can't walk '" .. path .. "' backwards (only directions can be): " ..
                "no way back, so no portal/instant training and no walking back.\n")
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
                print("Learning mode requires a target and the path from it to your rest spot," ..
                    " e.g. autolearn elder n;n;n;n;w")
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
