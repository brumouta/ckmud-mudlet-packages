-- Yamoshi spawn quest helper (Temple of the Ancient Saiyajins). Type `ys help` for commands.
-- Every stage starts and ends at The Echoing Atrium (the Temple Guardian's altar).
ys = ys or {}
local YS = ys

-- ---------------------------------------------------------------- settings
YS.attack = YS.attack or "ss"        -- attack used on the bosses
YS.vortex = "enter vortex"           -- the swirling vortexes between the hallways and the trials

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
  memory     = concat(rep("s", 4), YS.vortex, rep("e", 3)),    -- Kaizor's room -> Atrium
  perception = concat("n", "n", "e", "n", "n", "n", "w", rep("n", 5), YS.vortex, rep("s", 3)),  -- Varkuun -> Atrium
  power      = concat(rep("e", 10), YS.vortex, rep("w", 3)),   -- Renzakai -> Atrium
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
    trigs[2] = tempTrigger("Something feels wrong. The energy seems... copied, fragmented.", senseNext)
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

-- ---------------------------------------------------------------- `ys` alias
YS.HELP = {
  { "ys help",          "Show this list" },
  { "ys start [stage]", "Start from The Echoing Atrium (all trials, or from a stage)" },
  { "ys go",            "Restart the current stage - stand in the Atrium first" },
  { "ys stop",          "Turn the helper off and cancel whatever it's doing" },
  { "ys status",        "Show the current stage" },
  { "ys stage <name>",  "Set the stage: " .. table.concat(YS.STAGES, ", ") },
  { "ys attack <cmd>",  "Attack used on the bosses (default ss)" },
}

function YS.help()
  cecho("\n<cyan>Yamoshi spawn helper (ys) commands:\n")
  for _, row in ipairs(YS.HELP) do
    cecho(string.format("  <yellow>%-18s<white>%s\n", row[1], row[2]))
  end
end

function YS.status()
  cecho("\n<cyan>ys status:\n")
  cecho("  <white>Helper: " .. (YS.active and "<green>ON" or "<red>OFF") .. "<white>\n")
  cecho("  <white>Stage:  " .. YS.stage .. " - " .. (YS.HINTS[YS.stage] or "") .. "\n")
  cecho("  <white>Attack: " .. YS.attack .. "\n")
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
    info("yellow", "Helper OFF")
  elseif cmd == "stage" and arg and validStage(arg) then
    YS.setStage(arg)
  elseif cmd == "attack" and arg then
    YS.attack = arg
    info("white", "Attack set to '" .. arg .. "'")
  else
    info("yellow", "Unknown command. Type ys help")
  end
end
