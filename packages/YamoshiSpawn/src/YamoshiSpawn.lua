-- Yamoshi spawn quest helper (Temple of the Ancient Saiyajins). Type `ys help` for commands.
-- Every stage starts and ends at The Echoing Atrium (the Temple Guardian's altar).
ys = ys or {}
local YS = ys

-- ---------------------------------------------------------------- settings
YS.attack = YS.attack or "ss"        -- attack used on the bosses
YS.vortex = "enter vortex"           -- the swirling vortexes from the hallways into the trials
YS.exit   = "up"                     -- the way back out; the vortex doesn't take you out of a trial

-- ys fragments on|off: search for memory fragments on the portal walk and before each quiz
-- answer. Kept in a file in the profile, so it survives a restart.
local function settingsFile() return getMudletHomeDir and (getMudletHomeDir() .. "/yamoshispawn.lua") end
if YS.fragments == nil then
  YS.fragments = true
  local f, saved = settingsFile(), {}
  if f and table.load and io.open(f) then pcall(table.load, f, saved) end
  if saved.fragments ~= nil then YS.fragments = saved.fragments end
end

YS.STAGES = { "memory", "perception", "power", "ritual", "done" }
YS.HINTS = {
  memory     = "Trial of Memory (west hallway): four flames, then Warlord Kaizor.",
  perception = "Trial of Perception (north hallway): six chambers, then Ruthless Varkuun.",
  power      = "Trial of Power (east hallway): four Evil Shadow warriors, then Legendary Renzakai.",
  ritual     = "Back at the altar: say ritual to summon Yamoshi.",
  done       = "Yamoshi has been summoned.",
}

-- ---------------------------------------------------------------- state
YS.active = YS.active or false
YS.stage  = YS.stage or "memory"
YS.flames = {}        -- Trial of Memory order, e.g. { "Purpose", "Will", "Power", "Pride" }
YS.leg    = nil       -- which scripted leg is running, so repeated NPC lines don't restart it

local function info(color, msg) cecho("\n<" .. color .. ">[ys] " .. msg .. "\n") end
local function on(stage) return YS.active and YS.stage == stage end

local function rep(dir, n)
  local out = {}
  for i = 1, n do out[i] = dir end
  return out
end

local function concat(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    if type(part) == "table" then
      for _, s in ipairs(part) do out[#out + 1] = s end
    else
      out[#out + 1] = part
    end
  end
  return out
end

function YS.setStage(stage)
  YS.stage, YS.leg = stage, nil
  info("cyan", "Stage: " .. stage .. " - " .. (YS.HINTS[stage] or ""))
end

-- ---------------------------------------------------------------- step runner
-- Steps: a string is sent; { wait = "text" } / { waitRe = "regex" } pause until a line matches;
-- { async = function(next) } runs and continues when it calls next(). A wait that times out
-- stops the leg with a warning so you can finish by hand.
local runner = { queue = {} }

function YS.cancel()
  for _, id in ipairs(runner.trigs or {}) do killTrigger(id) end
  if runner.timer then killTimer(runner.timer) end
  runner.trigs, runner.timer, runner.queue = {}, nil, {}
end

local nextStep

local function pause(timeout, what)
  runner.timer = tempTimer(timeout, function()
    for _, id in ipairs(runner.trigs) do killTrigger(id) end
    runner.trigs, runner.timer, runner.queue = {}, nil, {}
    info("yellow", "Timed out waiting for: " .. what .. " - finish this part by hand, then `ys go` from the Atrium")
  end)
end

local function resume()
  for _, id in ipairs(runner.trigs) do killTrigger(id) end
  if runner.timer then killTimer(runner.timer) end
  runner.trigs, runner.timer = {}, nil
  nextStep()
end

nextStep = function()
  local step = table.remove(runner.queue, 1)
  if step == nil then return end
  if type(step) == "string" then
    send(step)
    return nextStep()
  end
  runner.trigs = {}
  if step.wait then
    runner.trigs[1] = tempTrigger(step.wait, resume)
    pause(step.timeout or 20, step.wait)
  elseif step.waitRe then
    runner.trigs[1] = tempRegexTrigger(step.waitRe, resume)
    pause(step.timeout or 20, step.label or step.waitRe)
  elseif step.async then
    step.async(function() nextStep() end)
  end
end

function YS.run(steps)
  YS.cancel()
  for _, s in ipairs(steps) do runner.queue[#runner.queue + 1] = s end
  nextStep()
end

-- Attack a boss and wait until it dies
local function kill(target, deathLine)
  return { YS.attack .. " " .. target, { wait = deathLine, timeout = 90 } }
end

-- ---------------------------------------------------------------- routes (from your log)
-- Atrium -> each trial's guardian, and the walk back after its boss
YS.ROUTE = {
  memory     = concat(rep("w", 3), YS.vortex, rep("n", 3)),    -- Hall of Memories
  perception = concat(rep("n", 3), YS.vortex, "s"),            -- Chamber of Twisted Reflection
  power      = concat(rep("e", 3), YS.vortex, "w"),            -- Hall of Champions
}
YS.BACK = {
  memory     = concat(rep("s", 4), YS.exit, rep("e", 3)),    -- Kaizor's room -> Atrium
  perception = concat("n", "n", "e", "n", "n", "n", "w", rep("n", 5), YS.exit, rep("s", 3)),  -- Varkuun -> Atrium
  power      = concat(rep("e", 10), YS.exit, rep("w", 3)),   -- Renzakai -> Atrium
}

-- ---------------------------------------------------------------- Trial of Memory
-- The four Chambers of Memories sit at the corners of a square loop around the
-- Forgotten Crossing (bottom middle). Coordinates: x west(-)/east(+), y north(+).
YS.TORCHES = {
  Pride   = { x = -2, y = 0 },
  Power   = { x = -2, y = 4 },
  Purpose = { x = 2,  y = 4 },
  Will    = { x = 2,  y = 0 },
}
local CROSSING = { x = 0, y = 0 }

-- Walk the loop from a to b (corners or the crossing)
function YS.loopRoute(a, b)
  local moves = {}
  local function horizontal(fromX, toX)
    local d = toX > fromX and "e" or "w"
    for _ = 1, math.abs(toX - fromX) do moves[#moves + 1] = d end
  end
  local function vertical(fromY, toY)
    local d = toY > fromY and "n" or "s"
    for _ = 1, math.abs(toY - fromY) do moves[#moves + 1] = d end
  end
  if math.abs(a.x) == 2 then          -- on a side: go up/down first, then across
    vertical(a.y, b.y); horizontal(a.x, b.x)
  else                                -- on the bottom edge: go across first, then up/down
    horizontal(a.x, b.x); vertical(a.y, b.y)
  end
  return moves
end

function YS.flameNamed(name)
  if on("memory") then YS.flames[#YS.flames + 1] = name end
end

-- "Remember them well, and seek them in the proper order."
function YS.memoryGo()
  if not on("memory") or YS.leg == "flames" then return end
  if #YS.flames ~= 4 then
    return info("yellow", "Only caught " .. #YS.flames .. " flame names - do this trial by hand")
  end
  YS.leg = "flames"
  info("white", "Flame order: " .. table.concat(YS.flames, ", "))
  local steps, pos = { "s" }, CROSSING           -- Hall of Memories -> crossing
  for _, name in ipairs(YS.flames) do
    local torch = YS.TORCHES[name]
    if not torch then return info("yellow", "Unknown flame '" .. name .. "' - do this trial by hand") end
    steps = concat(steps, YS.loopRoute(pos, torch), "extinguish",
                   { { wait = "The torch extinguishes with a burst of azure light!" } })
    pos = torch
  end
  steps = concat(steps, YS.loopRoute(pos, CROSSING), "n", "n",        -- up to Warlord Kaizor
                 kill("kaizor", "Warlord Kaizor is dead!  R.I.P."), YS.BACK.memory,
                 { { async = function(nxt) YS.setStage("perception"); YS.startStage(); nxt() end } })
  YS.run(steps)
end

-- ---------------------------------------------------------------- Trial of Perception
-- Hall of Uncertainty maze, from the top centre room (H0, two south of the guardian):
--   J1 4 west of H0, J2 4 east; L0 is 2 south of H0 with J3 2 east and J4 2 west;
--   M is 2 south of the room west of L0 (J5 3 west of M); M' is 2 south of the room
--   east of L0 (J6 3 east of M'). Varkuun is south of M' (s, w, s, s).
-- The guardian needs a while after "Very well" before the maze opens; until then moving
-- south only gets "You must start the trial to proceed." So walk in one room at a time
-- (guardian -> False Corridor -> first Hall of Uncertainty), and when blocked wait and look.
local ENTRY_ROOMS = [[^(Chamber of Twisted Reflection|False Corridor|Hall of Uncertainty)$]]
YS.ENTRY_RETRY = 2        -- seconds between attempts
YS.ENTRY_TRIES = 30       -- give up after this many refusals (about a minute)

local function enterMaze()
  return { async = function(nxt)
    local trigs, timer, tries = {}, nil, 0
    local function stop()
      for _, i in ipairs(trigs) do killTrigger(i) end
      if timer then killTimer(timer) end
      trigs, timer = {}, nil
    end
    local function later(secs, fn)
      if timer then killTimer(timer) end
      timer = tempTimer(secs, fn)
    end
    local function stuck(why)
      stop()
      YS.cancel()
      info("yellow", why .. " - finish the Trial of Perception by hand (chambers and Varkuun), go back to the Atrium, then `ys stage power` and `ys go`")
    end
    local function watchdog() later(10, function() stuck("The room never answered") end) end
    -- A room title tells us where we are. Wait a moment before moving, in case the
    -- "must start the trial" refusal is about to follow it.
    trigs[1] = tempRegexTrigger(ENTRY_ROOMS, function()
      if matches[2] == "Hall of Uncertainty" then
        stop()
        return nxt()
      end
      later(0.5, function() send("s"); watchdog() end)
    end)
    trigs[2] = tempTrigger("You must start the trial to proceed.", function()
      tries = tries + 1
      if tries > YS.ENTRY_TRIES then return stuck("The maze never opened") end
      if tries == 1 then info("white", "Waiting for the guardian to open the maze...") end
      later(YS.ENTRY_RETRY, function() send("look"); watchdog() end)
    end)
    send("s")
    watchdog()
  end }
end

local function solveChamber()
  -- sense Fat then Skinny; touch the first true one, or Muscular if both are false
  return { async = function(nxt)
    local suspects, i = { "fat", "ski" }, 0
    local trigs, timer = {}, nil
    local function done()
      for _, id in ipairs(trigs) do killTrigger(id) end
      if timer then killTimer(timer) end
      trigs, timer = {}, nil
    end
    -- Give up (rather than guess) if the game answers with a line we don't recognise
    local function expectReply(what)
      if timer then killTimer(timer) end
      timer = tempTimer(8, function()
        done()
        YS.cancel()
        info("yellow", "No recognisable reply to '" .. what .. "' - finish the chambers by hand, then `ys stage power` and `ys go` from the Atrium")
      end)
    end
    local function touch(who)
      done()
      send("touch " .. who)
      trigs[1] = tempTrigger("you have found truth!", function() done(); nxt() end)
      expectReply("touch " .. who)
    end
    local function senseNext()
      i = i + 1
      if not suspects[i] then return touch("mus") end
      send("sense " .. suspects[i])
      expectReply("sense " .. suspects[i])
    end
    trigs[1] = tempRegexTrigger([[^(This presence is solid, certain|The ki signature is stable and bright)]],
      function() touch(suspects[i]) end)
    -- an echo (either wording): sense the next one
    trigs[2] = tempTrigger("Something feels wrong. The energy seems... copied, fragmented.", senseNext)
    trigs[3] = tempTrigger("Cold and lifeless. An echo of a warrior, not the real thing.", senseNext)
    senseNext()
  end }
end

YS.PERCEPTION_TOUR = concat(
  { enterMaze() },                            -- guardian -> H0, waiting for the maze to open
  rep("w", 4), { solveChamber() },            -- J1
  rep("e", 8), { solveChamber() },            -- J2
  rep("w", 4), "s", "s", "e", "e", { solveChamber() },   -- J3
  rep("w", 4), { solveChamber() },            -- J4
  "e", "s", "s", rep("w", 3), { solveChamber() },        -- J5
  rep("e", 3), "n", "n", "e", "e", "s", "s", rep("e", 3), { solveChamber() },   -- J6
  rep("w", 3), "s", "w", "s", "s"             -- down to Visions of the First Saiyans
)

-- "Very well. Test your perception wisely."
function YS.perceptionGo()
  if not on("perception") or YS.leg == "chambers" then return end
  YS.leg = "chambers"
  YS.run(concat(YS.PERCEPTION_TOUR, kill("varkuun", "Ruthless Varkuun is dead!  R.I.P."), YS.BACK.perception,
                { { async = function(nxt) YS.setStage("power"); YS.startStage(); nxt() end } }))
end

-- ---------------------------------------------------------------- Trial of Power
-- From the Guardian of Might: 4 west is the centre of the Hall of Champions; 3 north and
-- 3 south of it are junctions with an Underground Arena east and west. Renzakai is 5 west.
local WARRIOR_DOWN = [[^(One warrior falls|Two warriors fall|Three warriors fall|All warriors defeated)!]]
local function killWarrior()
  return { YS.attack .. " evil", { waitRe = WARRIOR_DOWN, label = "an Evil Shadow warrior to fall", timeout = 90 } }
end

YS.POWER_TOUR = concat(
  rep("w", 4), rep("n", 3),                  -- north junction
  "e", killWarrior(), "w", "w", killWarrior(),
  "e", rep("s", 6),                          -- south junction
  "e", killWarrior(), "w", "w", killWarrior(),
  "e", rep("n", 3), rep("w", 5)              -- Arena of the First Saiyans
)

-- "Four warriors now descend to challenge you. Defeat them all!"
function YS.powerGo()
  if not on("power") or YS.leg == "warriors" then return end
  YS.leg = "warriors"
  YS.run(concat(YS.POWER_TOUR, kill("renzakai", "Legendary Renzakai is dead!  R.I.P."), YS.BACK.power,
                { { async = function(nxt) YS.setStage("ritual"); YS.startStage(); nxt() end } }))
end

-- ---------------------------------------------------------------- guardians and the ritual
function YS.guardianReady(stage)
  if on(stage) and YS.leg == "walk" then
    YS.leg = "ready"
    send("say ready")
  end
end

function YS.summoned()
  if not YS.active then return end
  YS.cancel()
  YS.setStage("done")
  YS.active = false
  info("green", "Yamoshi summoned - helper finished")
end

-- Walk from the Atrium to the current stage's guardian (or perform the ritual)
function YS.startStage()
  local s = YS.stage
  if s == "memory" then YS.flames = {} end
  if YS.ROUTE[s] then
    YS.leg = "walk"
    YS.run(YS.ROUTE[s])
  elseif s == "ritual" then
    YS.run({ "say ritual" })
  end
end

-- ---------------------------------------------------------------- Tetsukai's quiz
-- Tetsukai / Tetsusai ask about Yamoshi's story; answered whenever a known question shows up.
YS.QUIZ = {
  { "performed this to unlock Yamoshi's true potential", "ritual" },
  { "penned the Book of",                                "namek" },
  { "color of the aura that surrounded us",              "blue" },
  { "What was Yamoshi's ultimate fate",                  "death" },
  { "How many saiyans did Yamoshi seek out",             "5" },
  { "unlocked what ability in Yamoshi",                  "Super Saiyan God" },
  { "burned in the hearts of Yamoshi's comrades",        "Righteousness" },
  { "fought bravely to defeat which threat",             "Evil Saiyans" },
  { "what form did Yamoshi achieve",                     "SSJ" },
  { "seeking out comrades in arms",                      "Wander" },
}

-- With ys fragments on, every answer waits for a search first (and get fragment if it finds one)
local quizWait = {}
local function quizWaitStop()
  for _, id in ipairs(quizWait.trigs or {}) do killTrigger(id) end
  if quizWait.timer then killTimer(quizWait.timer) end
  quizWait = {}
end
YS.quizWaitStop = quizWaitStop

local function searchThenAnswer(answer)
  if quizWait.queue then   -- a search is already out: answer this one with it
    quizWait.queue[#quizWait.queue + 1] = answer
    return
  end
  local function finish(found)
    local queue = quizWait.queue or {}
    quizWaitStop()
    if found then send(YS.GRAB) end
    for _, a in ipairs(queue) do send("say " .. a) end
  end
  quizWait.queue = { answer }
  quizWait.trigs = {
    tempTrigger(YS.FRAGMENT_FOUND, function() finish(true) end),
    tempTrigger(YS.FRAGMENT_MISSED, function() finish(false) end),
  }
  quizWait.timer = tempTimer(YS.portalDelay, function() quizWait.timer = nil; finish(false) end)
  send(YS.SEARCH)
end

function YS.quiz(question)
  for _, qa in ipairs(YS.QUIZ) do
    if question:find(qa[1], 1, true) then
      if YS.fragments then searchThenAnswer(qa[2]) else send("say " .. qa[2]) end
      return qa[2]
    end
  end
end

-- ---------------------------------------------------------------- `ys portal`
-- The switch-and-portal walk. With ys fragments on, each room is searched and the walk moves on
-- as soon as the search answers; once a fragment turns up it's picked up and the rest of the
-- walk is sent straight away. With ys fragments off it just walks.
YS.FRAGMENT_FOUND = "After searching around you managed to uncover a fragment of memories!"
YS.FRAGMENT_MISSED = "You search around the area, but fail to find anything."
YS.SEARCH = "search"
YS.GRAB = "get fragment"
YS.portalDelay = YS.portalDelay or 5   -- seconds to wait for a search answer before moving on anyway
YS.PORTAL_ROOMS = {                    -- what to send after searching each room
  { "press switch", "press switch", "enter portal" },
  { "press switch", "enter portal" },
  { "press switch", "enter portal" },
  { "press switch", "press switch", "enter portal" },
  { "press switch", "enter portal" },
  { "press switch", "press switch", "enter portal" },
  {},
}

local walk = {}

function YS.portalStop()
  for _, id in ipairs(walk.trigs or {}) do killTrigger(id) end
  if walk.timer then killTimer(walk.timer) end
  walk = {}
end

local function sendRooms(from)
  for i = from, #YS.PORTAL_ROOMS do
    for _, cmd in ipairs(YS.PORTAL_ROOMS[i]) do send(cmd) end
  end
end

local searchRoom

-- The search in the current room came back empty (or never answered): move on
local function missed()
  if not walk.room then return end
  if walk.timer then killTimer(walk.timer) end
  walk.timer = nil
  local i = walk.room
  for _, cmd in ipairs(YS.PORTAL_ROOMS[i]) do send(cmd) end
  searchRoom(i + 1)
end

searchRoom = function(i)
  if i > #YS.PORTAL_ROOMS then
    YS.portalStop()
    return info("yellow", "ys portal: no fragment found")
  end
  walk.room = i
  send(YS.SEARCH)
  walk.timer = tempTimer(YS.portalDelay, missed)
end

function YS.portal(search)
  YS.portalStop()
  if not search then return sendRooms(1) end
  walk.trigs = {
    tempTrigger(YS.FRAGMENT_FOUND, function()
      local room = walk.room
      if not room then return end
      YS.portalStop()
      send(YS.GRAB)
      info("green", "ys portal: fragment found - skipping the other searches")
      sendRooms(room)
    end),
    tempTrigger(YS.FRAGMENT_MISSED, missed),
  }
  searchRoom(1)
end

-- ---------------------------------------------------------------- `ys spirits` (the Spirit Realm)
-- The ancient battlefields: Evil Saiyan Spirits on the west side, Righteous ones on the east.
-- sense takes you to one; kill it, sense again, until "No one is around by that name." Evils
-- first, then the righteous. Then, with ys fragments on, search every room for the fragment.
YS.SPIRITS = { { "evil", "Evil Saiyan Spirit" }, { "righteous", "Righteous Saiyan Spirit" } }
YS.NO_ONE = "No one is around by that name."
YS.SEARCH_ROOMS = { ["An ancient battlefield"] = true, ["a small corridor"] = true, ["an intersection"] = true }
YS.spiritTries = YS.spiritTries or 15   -- senses in a row that find nobody to hit before giving up

local sp = {}
local function spClear()
  for _, id in ipairs(sp.trigs or {}) do killTrigger(id) end
  if sp.timer then killTimer(sp.timer) end
  sp.trigs, sp.timer = {}, nil
end
function YS.spiritsStop() spClear(); sp = {} end
local function spWait(timeout, fn) if sp.timer then killTimer(sp.timer) end; sp.timer = tempTimer(timeout, function() sp.timer = nil; fn() end) end
local function spOn(text, fn) sp.trigs[#sp.trigs + 1] = tempTrigger(text, fn) end

local huntKind, searchAll

local function huntNext()
  sp.kind = sp.kind + 1
  local k = YS.SPIRITS[sp.kind]
  if not k then
    spClear()
    info("green", "ys spirits: the battlefields are clear")
    if YS.fragments then return searchAll() end
    sp = {}
    return
  end
  info("white", "ys spirits: hunting " .. k[2] .. "s")
  huntKind(k)
end

huntKind = function(k)
  spClear()
  sp.state, sp.misses = nil, 0
  local function sense()
    sp.misses = sp.misses + 1
    if sp.misses > YS.spiritTries then
      YS.spiritsStop()
      return info("yellow", "ys spirits: sensed " .. YS.spiritTries .. " times without finding a " .. k[2] .. " to hit - finish by hand")
    end
    sp.state = "sensing"
    send("sense " .. k[1])
    spWait(4, sense)          -- went somewhere with nobody to hit (it moved): sense again
  end
  local function attack()
    sp.state, sp.misses = "attacking", 0
    send(YS.attack .. " " .. k[1])
    spWait(90, sense)
  end
  spOn(YS.NO_ONE, function() if sp.state == "sensing" then huntNext() end end)
  spOn("You're already in the same room!!", function() if sp.state == "sensing" then attack() end end)
  spOn(k[2] .. " is standing here", function() if sp.state == "sensing" then attack() end end)
  spOn(k[2] .. " is dead!", function() if sp.state == "attacking" then sp.state = "dead"; spWait(0.5, sense) end end)
  spOn(" who?", function() if sp.state == "attacking" then sense() end end)   -- "Death Beam who?": it's gone
  sense()
end

function YS.spirits()
  YS.spiritsStop()
  sp = { kind = 0 }
  huntNext()
end

-- Search every room: walk them one by one (depth first, by the exits each room lists, keeping
-- to YS.SEARCH_ROOMS), search each, and stop at the first fragment.
local MOVE = { north = { 0, 1, 0, "n", "s" }, south = { 0, -1, 0, "s", "n" }, east = { 1, 0, 0, "e", "w" },
               west = { -1, 0, 0, "w", "e" }, up = { 0, 0, 1, "u", "d" }, down = { 0, 0, -1, "d", "u" } }
YS.EXIT_LINE = [[^(North|East|South|West|Up|Down)\s+-\s+(.+)$]]

searchAll = function()
  spClear()
  sp = { pos = { 0, 0, 0 }, seen = {}, back = {}, searches = 0, trigs = {} }
  local key = function(p) return p[1] .. "," .. p[2] .. "," .. p[3] end
  local step
  local function arrive(cb)      -- wait for the room's exits, then cb(exits)
    local exits, collecting = {}, false
    sp.trigs[#sp.trigs + 1] = tempTrigger("Obvious exits:", function()
      collecting = true
      spWait(0.5, function() spClear(); cb(exits) end)
    end)
    sp.trigs[#sp.trigs + 1] = tempRegexTrigger(YS.EXIT_LINE, function()
      if collecting then exits[#exits + 1] = { dir = matches[2]:lower(), to = (matches[3] or ""):gsub("%s+$", "") } end
    end)
    spWait(8, function() YS.spiritsStop(); info("yellow", "ys spirits: lost track of the rooms - search the rest by hand") end)
  end
  local function moveOn(exits)
    for _, e in ipairs(exits) do
      local m = MOVE[e.dir]
      if m and YS.SEARCH_ROOMS[e.to] then
        local np = { sp.pos[1] + m[1], sp.pos[2] + m[2], sp.pos[3] + m[3] }
        if not sp.seen[key(np)] then
          sp.back[#sp.back + 1] = m[5]; sp.pos = np
          send(m[4])
          return arrive(step)
        end
      end
    end
    local b = table.remove(sp.back)
    if not b then
      local n = sp.searches
      YS.spiritsStop()
      return info("yellow", "ys spirits: searched all " .. n .. " rooms, no fragment")
    end
    for _, m in pairs(MOVE) do if m[4] == b then sp.pos = { sp.pos[1] + m[1], sp.pos[2] + m[2], sp.pos[3] + m[3] } end end
    send(b)
    arrive(moveOn)
  end
  step = function(exits)
    sp.seen[key(sp.pos)] = true
    sp.searches = sp.searches + 1
    local done = false
    local function after(found)
      if done then return end
      done = true
      spClear()
      if found then
        local n = sp.searches
        send(YS.GRAB)
        YS.spiritsStop()
        return info("green", "ys spirits: fragment found in room " .. n .. " searched")
      end
      moveOn(exits)
    end
    sp.trigs[#sp.trigs + 1] = tempTrigger(YS.FRAGMENT_FOUND, function() after(true) end)
    sp.trigs[#sp.trigs + 1] = tempTrigger(YS.FRAGMENT_MISSED, function() after(false) end)
    spWait(YS.portalDelay, function() after(false) end)
    send(YS.SEARCH)
  end
  info("white", "ys spirits: searching every room for the fragment")
  send("look")
  arrive(step)
end
function YS.searchRooms() YS.spiritsStop(); searchAll() end

-- ---------------------------------------------------------------- `ys` alias
YS.HELP = {
  { "ys help",          "Show this list" },
  { "ys start [stage]", "Start from The Echoing Atrium (all trials, or from a stage)" },
  { "ys go",            "Restart the current stage - stand in the Atrium first" },
  { "ys stop",          "Turn the helper off and cancel whatever it's doing" },
  { "ys status",        "Show the current stage" },
  { "ys stage <name>",  "Set the stage: " .. table.concat(YS.STAGES, ", ") },
  { "ys attack <cmd>",  "Attack used on the bosses (default ss)" },
  { "ys portal",        "Walk the switches and portals (with fragments on: searching until a fragment turns up)" },
  { "ys spirits",       "Spirit Realm battlefields: sense and kill every Evil, then every Righteous Saiyan Spirit, then search every room (fragments on)" },
  { "ys search",        "Search every battlefield room for the fragment (stops at the first)" },
  { "ys fragments [on|off]", "Search for memory fragments on the portal walk and before each quiz answer (default on)" },
}

function YS.help()
  cecho("\n<cyan>Yamoshi spawn helper (ys) commands:\n")
  for _, row in ipairs(YS.HELP) do
    cecho(string.format("  <yellow>%-22s<white>%s\n", row[1], row[2]))
  end
end

function YS.status()
  cecho("\n<cyan>ys status:\n")
  cecho("  <white>Helper: " .. (YS.active and "<green>ON" or "<red>OFF") .. "<white>\n")
  cecho("  <white>Stage:  " .. YS.stage .. " - " .. (YS.HINTS[YS.stage] or "") .. "\n")
  cecho("  <white>Attack: " .. YS.attack .. "\n")
  cecho("  <white>Fragments: " .. (YS.fragments and "<green>ON" or "<red>OFF") .. "<white>\n")
end

local function validStage(name)
  for _, s in ipairs(YS.STAGES) do if s == name then return true end end
end

function YS.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    YS.help()
  elseif cmd == "status" then
    YS.status()
  elseif cmd == "start" then
    if arg and not validStage(arg) then return info("yellow", "Unknown stage '" .. arg .. "'") end
    YS.active = true
    YS.setStage(arg or "memory")
    YS.startStage()
  elseif cmd == "go" then
    YS.active = true
    YS.setStage(YS.stage)
    YS.startStage()
  elseif cmd == "stop" then
    YS.active, YS.leg = false, nil
    YS.cancel()
    YS.portalStop()
    quizWaitStop()
    YS.spiritsStop()
    info("yellow", "Helper OFF")
  elseif cmd == "stage" and arg and validStage(arg) then
    YS.setStage(arg)
  elseif cmd == "spirits" then
    YS.spirits()
  elseif cmd == "search" then
    YS.searchRooms()
  elseif cmd == "portal" then
    YS.portal(YS.fragments)
  elseif cmd == "fragments" or cmd == "fragment" then
    if arg == "on" then YS.fragments = true elseif arg == "off" then YS.fragments = false
    elseif arg == nil then YS.fragments = not YS.fragments
    else return info("yellow", "ys fragments on or off") end
    local f = settingsFile()
    if f and table.save then pcall(table.save, f, { fragments = YS.fragments }) end
    info("white", "Fragments: " .. (YS.fragments and "on - ys portal and the quiz search first" or "off - no searching"))
  elseif cmd == "attack" and arg then
    YS.attack = arg
    info("white", "Attack set to '" .. arg .. "'")
  else
    info("yellow", "Unknown command. Type ys help")
  end
end
