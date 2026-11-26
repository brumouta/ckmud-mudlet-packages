-- Frieza's Spaceship quest helper. Type `fq help` for commands.
fq = fq or {}
local FQ = fq

-- ---------------------------------------------------------------- settings
FQ.attack    = FQ.attack or "ss"                 -- attack used on the bosses
FQ.passwords = { "dief", "epikoin", "kinitiras", "exousia" }  -- one of these opens each hatch

-- Items the quest uses up: { keyword for `locate`, item name, stage that consumes it }
FQ.ITEMS = {
  { "evermore", "Evermore Fusion Cell",  "steering" },
  { "tufftech", "TuffTech x45 battery",  "power" },
  { "matter",   "lump of dark matter",   "power" },
  { "premium",  "premium circuit board", "power" },
}

-- Stages in quest order
FQ.STAGES = { "appule", "cuicui", "engine", "steering", "revenge", "comms", "power", "comms2", "zarbon", "bridge", "done" }
FQ.HINTS = {
  appule   = "Go to the Airlock with Appule (north or south of the Entrance to Frieza's Spaceship).",
  cuicui   = "Walking to Cui Cui (Cui Cui can't be sensed): from the Hatch, `fq go` walks there.",
  engine   = "Walking to the Engine Hatch (from Frieza's room, or `fq go` in the Gangway by the Elite Quarters).",
  steering = "Heading to the Steering Module.",
  revenge  = "Walking to the Rejuvenation Chamber (from the Steering Hatch; elsewhere: Starboard, the room with North/South - Rejuvenation Chamber, then north).",
  comms    = "Heading to the Communications Module.",
  power    = "Heading to the Power Module.",
  comms2   = "Heading back to the Communications Officer.",
  zarbon   = "Zarbon's interrogation - the bot will hand over the cards.",
  bridge   = "Walking to the Bridge terminal (from Taiko's room or the Hatch, `fq go`), then swipe and biometrics.",
  done     = "The Bridge is open. The rest of the quest isn't automated yet.",
}

-- ---------------------------------------------------------------- state
FQ.active   = FQ.active or false
FQ.stage    = FQ.stage or "appule"
FQ.password = FQ.password or nil
FQ.roomName = FQ.roomName or nil  -- last "Frieza's Spaceship: <room>" seen
FQ.exits    = {}      -- exits of the last room shown: { West = "Frieza's Spaceship: Power Hatch", ... }
FQ.pursuing = nil     -- what we're tracking with pursue, so the arrival is handled once
FQ.leg      = nil     -- the scripted leg currently running (guards against repeated room lines)

local function info(color, msg) cecho("\n<" .. color .. ">[fq] " .. msg .. "\n") end

local function on(stage) return FQ.active and FQ.stage == stage end

function FQ.setStage(stage)
  FQ.stage, FQ.leg = stage, nil
  info("cyan", "Stage: " .. stage .. " - " .. (FQ.HINTS[stage] or ""))
end

-- ---------------------------------------------------------------- step runner
-- A leg is a list of steps: a string is sent; { wait = "text" } pauses until that text
-- shows up; { fn = f } calls f. Legs stop (with a warning) if a wait times out.
local runner = { queue = {} }

function FQ.cancel()
  if runner.trig then killTrigger(runner.trig) end
  if runner.trig2 then killTrigger(runner.trig2) end
  if runner.timer then killTimer(runner.timer) end
  runner.trig, runner.trig2, runner.timer, runner.queue = nil, nil, nil, {}
end

local function nextStep()
  local step = table.remove(runner.queue, 1)
  if step == nil then return end
  if type(step) == "string" then
    send(step)
    return nextStep()
  end
  if step.fn then
    step.fn()
    return nextStep()
  end
  if step.use then   -- { use = { keyword, item name, command } }: locate, act on it by number, then go on
    local u = step.use
    return FQ.useFromLocate(u[1], u[2], u[3], function() nextStep() end)
  end
  if step.search then   -- on the way to the Engine Hatch: search each Engine Module room for the card
    if not (on("engine") and not FQ.haveCard and FQ.roomName == "Engine Module") then return nextStep() end
    local function done(extra)
      killTrigger(runner.trig); killTrigger(runner.trig2); killTimer(runner.timer)
      runner.trig, runner.trig2, runner.timer = nil, nil, nil
      if extra then send(extra) end
      nextStep()
    end
    runner.trig = tempTrigger("You search around the area, but fail to find anything.", function() done() end)
    runner.trig2 = tempRegexTrigger([[^After searching around you managed to uncover (.+)!$]], function()
      done(matches[2] == "Engine Module Access Card" and "get card" or nil)
    end)
    runner.timer = tempTimer(10, function() done() end)
    send("search")
    return
  end
  if step.delay then
    runner.timer = tempTimer(step.delay, function() runner.timer = nil; nextStep() end)
    return
  end
  if step.wait then
    runner.trig = tempTrigger(step.wait, function()
      killTrigger(runner.trig); killTimer(runner.timer)
      runner.trig, runner.timer = nil, nil
      nextStep()
    end)
    runner.timer = tempTimer(step.timeout or 20, function()
      killTrigger(runner.trig)
      runner.trig, runner.timer, runner.queue = nil, nil, {}
      info("yellow", "Timed out waiting for: " .. step.wait .. " - finish this part by hand, then `fq go`")
    end)
  end
end

function FQ.run(steps)
  FQ.cancel()
  for _, s in ipairs(steps) do runner.queue[#runner.queue + 1] = s end
  nextStep()
end

-- Say every hatch password, wait for the hatch to open, then go through it
function FQ.hatch(dir)
  local steps = {}
  for _, word in ipairs(FQ.passwords) do steps[#steps + 1] = "say " .. word end
  steps[#steps + 1] = { wait = "With the voice pattern confirmed, the hatch swings open." }
  steps[#steps + 1] = dir
  return steps
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

function FQ.pursue(target)
  FQ.pursuing = target:lower()
  send("pursue " .. target)
end

-- ---------------------------------------------------------------- items
local function stageIndex(stage)
  for i, s in ipairs(FQ.STAGES) do if s == stage then return i end end
  return 1
end

-- Items still needed when starting at `stage` (ones used by later stages)
function FQ.itemsFor(stage)
  local needed = {}
  for _, item in ipairs(FQ.ITEMS) do
    if stageIndex(item[3]) >= stageIndex(stage) then needed[#needed + 1] = item end
  end
  return needed
end

-- `locate` each item one at a time; done(missingNames) when all are checked.
-- Output looks like: "Your scouter scans your inventory for 'x'..." / o---o / results / o---o
function FQ.checkItems(items, done)
  local missing, i = {}, 0
  local function checkNext()
    i = i + 1
    local item = items[i]
    if not item then return done(missing) end
    local found, started, seps = false, false, 0
    local trigs, timer = {}, nil
    local function finish(ok)
      for _, id in ipairs(trigs) do killTrigger(id) end
      killTimer(timer)
      if not ok then return info("yellow", "Couldn't read the locate output - check your items, then `fq start` again") end
      if not found then missing[#missing + 1] = item[2] end
      checkNext()
    end
    trigs[1] = tempTrigger("Your scouter scans your inventory for", function() started = true end)
    trigs[2] = tempTrigger(item[2], function() if started then found = true end end)
    trigs[3] = tempRegexTrigger([[^o-+o$]], function()
      if not started then return end
      seps = seps + 1
      if seps == 2 then finish(true) end
    end)
    timer = tempTimer(5, function() finish(false) end)
    send("locate " .. item[1])
  end
  checkNext()
end

-- ---------------------------------------------------------------- module search
-- The lower module rooms are laid out the same way: A (arrival, under the hatch),
-- B south of A, C east of B, D north of A, E east of D. Search each until the card turns up.
local SEARCH_ROUTE = { { pos = "A" }, { move = "s", pos = "B" }, { move = "e", pos = "C" },
                       { move = "w", pos = "B", skip = true }, { move = "n", pos = "A", skip = true },
                       { move = "n", pos = "D" }, { move = "e", pos = "E" } }
local BACK_TO_A = { A = {}, B = { "n" }, C = { "w", "n" }, D = { "s" }, E = { "w", "s" } }

function FQ.searchForCard(onFound)
  local i, pos = 0, "A"
  local fail, found
  local function cleanup() if fail then killTrigger(fail) end; if found then killTrigger(found) end end
  local function nextRoom()
    i = i + 1
    local step = SEARCH_ROUTE[i]
    if not step then
      cleanup()
      return info("yellow", "Searched every room without finding the card - search by hand, then `fq go`")
    end
    if step.move then send(step.move) end
    pos = step.pos
    if step.skip then return nextRoom() end
    send("search")
  end
  fail = tempTrigger("You search around the area, but fail to find anything.", nextRoom)
  found = tempRegexTrigger([[^After searching around you managed to uncover (.+)!$]], function()
    cleanup()
    onFound(BACK_TO_A[pos])
  end)
  nextRoom()
end

-- ---------------------------------------------------------------- room tracking
function FQ.room(name)
  FQ.roomName, FQ.exits = name, {}
end

function FQ.exit(dir, dest)
  FQ.exits[dir] = dest
end

-- Which way an exit leading to `dest` is, as a command ("n", "s", ...), from the last room shown
function FQ.exitTo(dest)
  for dir, to in pairs(FQ.exits) do
    if to:find(dest, 1, true) then return dir:sub(1, 1):lower() end
  end
end

-- "You have successfully tracked down X!" or "You're already in the same room!!"
function FQ.arrived(who)
  if not FQ.active or not FQ.pursuing then return end
  if who and not who:lower():find(FQ.pursuing, 1, true) then return end
  FQ.pursuing = nil

  if FQ.stage == "steering" then
    FQ.run({ "s", "e" })                      -- to the Steering Hatch, the Technician takes over
  elseif FQ.stage == "comms" or FQ.stage == "comms2" then
    FQ.run(concat("n", "e", FQ.hatch("d"), "s", "e"))   -- down to the Communications Officer
  elseif FQ.stage == "power" then
    local toHatch = {}
    if not (FQ.exits.West or ""):find("Power Hatch", 1, true) then toHatch = { "s" } end
    FQ.run(concat(toHatch, "w", FQ.hatch("d"), "n", "e"))  -- down to the Electrical Engineer
  end
  -- revenge: tracked Dodoria, the room triggers take it from there
end

-- "No one is around by that name." - same as no ki: say where to walk
function FQ.noKi()
  if not FQ.active or not FQ.pursuing then return end
  if FQ.stage == "revenge" and FQ.pursuing == "dodoria" then
    FQ.pursuing = nil
    if FQ.retryDodoria() then return end
    return info("yellow", "Still can't find Dodoria - look for him by hand (`pursue dodoria`)")
  end
  info("yellow", "Can't pursue " .. FQ.pursuing .. " from here. " .. (FQ.HINTS[FQ.stage] or ""))
  FQ.pursuing = nil
end

-- ---------------------------------------------------------------- quest events
function FQ.appuleHere()
  if on("appule") then send(FQ.attack .. " appule") end
end

function FQ.appuleDead()
  if not on("appule") then return end
  -- Appule's Airlock is either north or south of the Entrance
  local toEntrance = FQ.exitTo("Entrance to Frieza's Spaceship") or "n"
  -- the Hatch (east of the Entrance) stays sealed until the game says so: going east
  -- before that only bumps into the closed hatch
  FQ.run({ "get caps", toEntrance,
           { wait = "The seals of the Hatch automatically release", timeout = 20 } })
end

-- Hatch -> Cui Cui's Personal Room. Cui Cui can't be sensed, so pursue doesn't work.
FQ.TO_CUI = { "n", "n", "n", "n", "n", "n", "n",   -- Passageway up to the Port
              "e", "n", "e", "n", "e", "n", "e", "e", -- Port, Forward, to the room above the Gangway
              "s", "s", "s", "s", "w", "s" }          -- Gangway, Elite Quarters, Cui Cui

-- Gangway (between the two Elite Quarters) -> Engine Hatch: up to the Forward rooms,
-- round the starboard side, all the way down the Passageways, into the Engine Module.
FQ.TO_ENGINE = { "n", "n", "n", "n",                      -- Gangway up to Forward
                 "e", "e", "s", "e", "s", "e", "s", "e",  -- Forward, Starboard
                 "s", "s", "s", "s", "s", "s", "s", "s", "s", "s", "s", "s", "s", "s", -- Passageways
                 "w", "s", "w", "n", "n", "n", "w" }      -- Starboard, Engine Module, Engine Hatch

-- Hatch -> the Gangway with the Bridge's Computer Terminal: up to the Forward rooms like
-- the Cui Cui walk, then 8 south down the Gangway (past the Elite Quarters)
FQ.TO_BRIDGE = { "n", "n", "n", "n", "n", "n", "n", "e", "n", "e", "n", "e", "n", "e", "e",
                 "s", "s", "s", "s", "s", "s", "s", "s" }
-- Taiko's room (the east end of the Crew Access Arm) -> Hatch
FQ.TAIKO_TO_HATCH = { "w", "w", "w" }

-- Steering Hatch -> Rejuvenation Chamber: up the Steering Module to the Port, across the
-- Forward rooms, round to the Starboard side, 7 south to the Airbridge crossing, east, north.
FQ.TO_REJUV = { "w", "n", "n", "n", "n",
                "e", "n", "e", "e", "e", "e", "s", "e", "s", "e", "s", "e",
                "s", "s", "s", "s", "s", "s", "s", "e", "n" }
-- Dodoria's Personal Room (north of the west Elite Quarters) -> Rejuvenation Chamber
FQ.DODORIA_TO_REJUV = { "s", "e", "n", "n", "n", "n",
                        "e", "e", "s", "e", "s", "e", "s", "e",
                        "s", "s", "s", "s", "s", "s", "s", "e", "n" }

-- A walk that waits for each room before the next move, so a card spotted on the way
-- can be picked up in its room
function FQ.walkSteps(route)
  local steps = {}
  for _, dir in ipairs(route) do
    steps[#steps + 1] = dir
    steps[#steps + 1] = { wait = "Obvious exits:", timeout = 15 }
    steps[#steps + 1] = { delay = 0.5 }             -- the room's items come after the exits
    steps[#steps + 1] = { search = true }           -- only in the Engine Module rooms, while looking for the card
  end
  return steps
end

function FQ.sealReleased()
  if not on("appule") then return end
  FQ.setStage("cuicui")
  FQ.run(concat("e", FQ.TO_CUI))
end

function FQ.cuiHere()
  if on("cuicui") then send(FQ.attack .. " cui") end
end

function FQ.gotPassword(code)
  FQ.password = code
  info("green", "Frieza's door code: " .. code)
end

function FQ.cuiDead()
  if not on("cuicui") then return end
  if not FQ.password then return info("yellow", "Didn't catch the door code - type `fq code <number>` then `fq go`") end
  tempTimer(1, function()
    -- the door takes a moment to open after the code; wear the armor by its `locate` number
    FQ.run(concat({ "n", "e", "e", "enter " .. FQ.password, { wait = "enters a code into the computer", timeout = 10 },
                    { delay = 2 }, "n", "get all locker", { use = { "battle", "Frieza's Battle Armor", "wear %s" } },
                    "s", "w" }, FQ.walkSteps(FQ.TO_ENGINE)))
    FQ.setStage("engine")
  end)
end

function FQ.noAccess()
  if not FQ.active then return end
  FQ.cancel()
  FQ.leg = nil
  info("yellow", "No access - wear Frieza's Battle Armor first (stage cuicui)")
end

-- Engine Hatch: "An Engineer is rummaging around frantically in search of something."
function FQ.engineHatch()
  if not on("engine") or FQ.leg or FQ.haveCard then return end   -- with the card, the Engineer asks for it
  FQ.leg = "engine"
  FQ.run(concat(FQ.hatch("d"), { { fn = function()
    FQ.searchForCard(function(back)
      FQ.run(concat("get card", back, FQ.hatch("u")))
    end)
  end } }))
end

-- "Engine Module Access Card was carelessly left here. (hidden)": it isn't always downstairs
function FQ.cardSpotted()
  if not on("engine") or FQ.haveCard then return end
  info("green", "The Engine card is in this room")
  local steps = { "search", { wait = "managed to uncover Engine Module Access Card", timeout = 10 }, "get card" }
  for i = #steps, 1, -1 do table.insert(runner.queue, 1, steps[i]) end   -- before the next move
  if not runner.trig and not runner.timer then nextStep() end           -- (not walking: do it now)
end

function FQ.gotCard() if on("engine") then FQ.haveCard = true end end

-- `locate <keyword>`, then act on the item by its number in that list ("give 3.card engineer",
-- "wear 2.battle"): a plain keyword can pick the wrong item ("wear battle" floated Paragus'
-- Battle Acumen; "give card" can pick a casino card). cmd is e.g. "give %s engineer" or "wear %s".
function FQ.useFromLocate(keyword, itemName, cmd, done)
  local trigs, timer, num, finished = {}, nil, nil, false
  local function finish()
    if finished then return end
    finished = true
    for _, id in ipairs(trigs) do killTrigger(id) end
    killTimer(timer)
    if num then send(string.format(cmd, num .. "." .. keyword))
    else info("yellow", "Couldn't find " .. itemName .. " with `locate " .. keyword .. "` - do it by hand") end
    if done then done() end
  end
  trigs[1] = tempRegexTrigger([[^#(\d+)\. (.+)$]], function()
    if not num and matches[3]:sub(1, #itemName) == itemName then num = matches[2] end
  end)
  trigs[2] = tempTrigger("Total items displayed:", finish)
  timer = tempTimer(5, finish)
  send("locate " .. keyword)
end

function FQ.engineerWantsCard()
  if on("engine") then FQ.useFromLocate("card", "Engine Module Access Card", "give %s engineer") end
end

function FQ.gotUniform()
  if not on("engine") then return end
  FQ.haveCard = false
  FQ.setStage("steering")
  FQ.useFromLocate("uniform", "An Engineer's Uniform", "wear %s", function() FQ.pursue("steering") end)
end

-- Steering Hatch: "We have an emergency! Are you the engineer we called for?"
function FQ.technicianAsks()
  if not on("steering") or FQ.leg then return end
  FQ.leg = "steering"
  FQ.run(concat(FQ.hatch("d"), "s", "e", "repair"))
end

function FQ.steeringOnline()
  if on("steering") then FQ.run(concat("w", "n", FQ.hatch("u"))) end
end

function FQ.steeringDone()
  if not on("steering") then return end
  FQ.setStage("revenge")
  FQ.run(FQ.walkSteps(FQ.TO_REJUV))     -- the dying man can never be pursued
end

function FQ.dyingMan()
  if on("revenge") then send("say revenge") end
end

-- Dodoria takes a while to spawn after the dying man names him: wait, then pursue, and
-- retry (noKi) every few seconds until he can be tracked
FQ.DODORIA_WAIT, FQ.DODORIA_RETRY, FQ.DODORIA_TRIES = 5, 5, 12

local function stopDodoriaTimer()
  if FQ.dodoriaTimer then killTimer(FQ.dodoriaTimer); FQ.dodoriaTimer = nil end
end

local function pursueDodoriaIn(secs)
  stopDodoriaTimer()
  FQ.dodoriaTimer = tempTimer(secs, function()
    FQ.dodoriaTimer = nil
    if on("revenge") then FQ.pursue("dodoria") end
  end)
end

function FQ.dodoriaNamed()
  if not on("revenge") then return end
  FQ.dodoriaTries = 0
  info("green", "Waiting " .. FQ.DODORIA_WAIT .. "s for Dodoria to spawn, then pursuing him")
  pursueDodoriaIn(FQ.DODORIA_WAIT)
end

-- "You sense no ki." / "No one is around by that name." while pursuing Dodoria
function FQ.retryDodoria()
  FQ.dodoriaTries = (FQ.dodoriaTries or 0) + 1
  if FQ.dodoriaTries >= FQ.DODORIA_TRIES then return false end
  pursueDodoriaIn(FQ.DODORIA_RETRY)
  return true
end

function FQ.dodoriaHere()
  if not on("revenge") then return end
  stopDodoriaTimer()
  send(FQ.attack .. " dodoria")
end

function FQ.dodoriaDead()
  if not on("revenge") then return end
  tempTimer(1, function()
    if FQ.roomName == "Dodoria's Personal Room" then FQ.run(FQ.walkSteps(FQ.DODORIA_TO_REJUV))
    else info("yellow", "Walk to the Rejuvenation Chamber (Starboard, the room with North/South - Rejuvenation Chamber, then north) - from the Steering Hatch or Dodoria's room, `fq go` walks there") end
  end)
end

function FQ.avenged()
  if not on("revenge") then return end
  FQ.setStage("comms")
  FQ.pursue("communications")
end

-- "Communications Officer says, 'If so, give it to me.'"
function FQ.officerAsks()
  if on("comms") then send("give dying comm")
  elseif on("comms2") then send("give crum comm") end
end

function FQ.needPower()
  if not on("comms") then return end
  FQ.setStage("power")
  FQ.run(concat("w", "n", FQ.hatch("u"), { { fn = function() FQ.pursue("power") end } }))
end

function FQ.engineerIdle()
  if on("power") then info("yellow", "The Electrical Engineer wants the parts: TuffTech x45 battery, premium circuit board, lump of dark matter - check with `fq check`") end
end

function FQ.powerDone()
  if not on("power") then return end
  FQ.setStage("comms2")
  FQ.run(concat("w", "s", FQ.hatch("u"), { { fn = function() FQ.pursue("communications") end } }))
end

-- "Communications Officer sends out an alert to make Zarbon aware of the situation."
-- Zarbon is in the room to the west: step in a second later and he starts the interrogation
function FQ.zarbonAlerted()
  if not on("comms2") then return end
  FQ.setStage("zarbon")
  FQ.run({ { delay = 1 }, "w" })
end

function FQ.zarbonAsks()
  if not FQ.active then return end
  if FQ.stage == "comms2" then FQ.setStage("zarbon") end
  if FQ.stage == "zarbon" then send("say surrender") end
end

-- "These are duplicates...nice try!": the Holding Room is still safe at that moment; Zarbon
-- can be attacked once the room is shown again with him in it ("[BOSS] Zarbon is here")
function FQ.duplicates()
  if on("zarbon") then FQ.zarbonFight = true end
end

function FQ.zarbonHere()
  if on("zarbon") and FQ.zarbonFight then
    FQ.zarbonFight = false
    send(FQ.attack .. " zarbon")
  end
end

function FQ.zarbonDead()
  if on("zarbon") then FQ.run({ "get all", "d" }) end
end

function FQ.bridgeCard()
  if not on("zarbon") then return end
  FQ.setStage("bridge")
  FQ.run(concat({ { delay = 1 } }, FQ.bridgeSteps(FQ.TAIKO_TO_HATCH)))
end

-- Walk (optionally from Taiko's room) to the Bridge terminal, swipe, biometrics
function FQ.bridgeSteps(first)
  return concat(FQ.walkSteps(concat(first or {}, FQ.TO_BRIDGE)),
                { "swipe", { wait = "Biometrics required.", timeout = 10 }, "biometrics" })
end

-- "Identity confirmed. Bridge portal opening."
function FQ.bridgeOpen()
  if not on("bridge") then return end
  FQ.cancel()
  FQ.setStage("done")
  FQ.active = false
  info("green", "Quest automation finished - the Bridge is open")
end

-- ---------------------------------------------------------------- `fq` alias
FQ.HELP = {
  { "fq help",            "Show this list" },
  { "fq start [stage]",   "Check the quest items, then turn the helper on (from the Airlock, or a stage)" },
  { "fq check",           "Check the quest items without starting" },
  { "fq stop",            "Turn the helper off and cancel whatever it's doing" },
  { "fq status",          "Show the current stage and settings" },
  { "fq go",              "Re-run the current stage's step from where you're standing" },
  { "fq stage <name>",    "Jump to a stage: " .. table.concat(FQ.STAGES, ", ") },
  { "fq code <number>",   "Set Frieza's door code by hand" },
  { "fq attack <cmd>",    "Attack used on the bosses (default ss)" },
  { "fq update",          "Update FriezaQuest to the latest release" },
}

function FQ.help()
  cecho("\n<cyan>Frieza quest helper (fq) commands:\n")
  for _, row in ipairs(FQ.HELP) do
    cecho(string.format("  <yellow>%-20s<white>%s\n", row[1], row[2]))
  end
end

function FQ.status()
  cecho("\n<cyan>fq status:\n")
  cecho("  <white>Helper: " .. (FQ.active and "<green>ON" or "<red>OFF") .. "<white>\n")
  cecho("  <white>Stage:  " .. FQ.stage .. " - " .. (FQ.HINTS[FQ.stage] or "") .. "\n")
  cecho("  <white>Code:   " .. (FQ.password or "-") .. "   Attack: " .. FQ.attack .. "\n")
end

local function validStage(name)
  for _, s in ipairs(FQ.STAGES) do if s == name then return true end end
end

-- Re-trigger the current stage from where you're standing
function FQ.go()
  FQ.active, FQ.leg = true, nil
  FQ.cancel()
  local s = FQ.stage
  if s == "appule" then FQ.appuleHere()
  elseif s == "cuicui" then
    if FQ.password then FQ.cuiDead()
    elseif FQ.roomName == "Hatch" then FQ.run(FQ.TO_CUI)
    else info("yellow", "Go to the Hatch (east of the Entrance) and `fq go` again, or walk: Gangway -> west (Elite Quarters) -> south") end
  elseif s == "engine" then
    -- the passwords only work at the Engine Hatch (where the Engineer rummages around)
    if FQ.roomName == "Engine Hatch" then FQ.engineHatch()
    elseif (FQ.exits.West or ""):find("Engine Hatch", 1, true) then send("w")
    elseif FQ.roomName == "Gangway" and (FQ.exits.West or ""):find("Elite Quarters", 1, true) then
      FQ.run(FQ.walkSteps(FQ.TO_ENGINE))
    else info("yellow", "Go to the Gangway between the Elite Quarters and `fq go` again") end
  elseif s == "steering" then FQ.pursue("steering")
  elseif s == "revenge" then
    if FQ.roomName == "Steering Hatch" then FQ.run(FQ.walkSteps(FQ.TO_REJUV))
    elseif FQ.roomName == "Dodoria's Personal Room" then FQ.run(FQ.walkSteps(FQ.DODORIA_TO_REJUV))
    else info("yellow", "Walk to the Rejuvenation Chamber (Starboard, the room with North/South - Rejuvenation Chamber, then north) - from the Steering Hatch or Dodoria's room, `fq go` walks there") end
  elseif s == "comms" or s == "comms2" then FQ.pursue("communications")
  elseif s == "power" then FQ.pursue("power")
  elseif s == "bridge" then
    if FQ.roomName == "Hatch" then FQ.run(FQ.bridgeSteps())
    elseif FQ.roomName == "Crew Access Arm" and FQ.exits.West and not FQ.exits.East then FQ.run(FQ.bridgeSteps(FQ.TAIKO_TO_HATCH))
    elseif FQ.roomName == "Gangway" and FQ.exits.North and not FQ.exits.South then
      FQ.run({ "swipe", { wait = "Biometrics required.", timeout = 10 }, "biometrics" })
    else info("yellow", "Go to Taiko's room or the Hatch and `fq go` again") end
  elseif s == "zarbon" and (FQ.exits.West or ""):find("Communications Module", 1, true) and not FQ.exits.North then
    send("w")                                 -- from the Officer's room to Zarbon
  else info("white", FQ.HINTS[s] or "") end
end

function FQ.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    FQ.help()
  elseif cmd == "status" then
    FQ.status()
  elseif cmd == "start" or cmd == "check" then
    if arg and not validStage(arg) then return info("yellow", "Unknown stage '" .. arg .. "'") end
    local stage = arg or (cmd == "start" and "appule") or FQ.stage
    FQ.checkItems(FQ.itemsFor(stage), function(missing)
      if #missing > 0 then
        info("red", "Missing: " .. table.concat(missing, ", ") .. (cmd == "start" and " - helper not started" or ""))
        return
      end
      info("green", "All quest items present")
      if cmd == "start" then
        FQ.active = true
        FQ.setStage(stage)
      end
    end)
  elseif cmd == "stop" then
    FQ.active, FQ.leg, FQ.pursuing = false, nil, nil
    FQ.cancel()
    info("yellow", "Helper OFF")
  elseif cmd == "go" or cmd == "run" then
    FQ.go()
  elseif cmd == "stage" and arg and validStage(arg) then
    FQ.setStage(arg)
  elseif cmd == "code" and arg then
    FQ.gotPassword(arg)
  elseif cmd == "attack" and arg then
    FQ.attack = arg
    info("white", "Attack set to '" .. arg .. "'")
  else
    info("yellow", "Unknown command. Type fq help")
  end
end
