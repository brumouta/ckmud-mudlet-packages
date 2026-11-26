-- FusionQuest: the West Capital questline that ends in the Metamoran fusion dance. Type `fus help`.
-- Chief Doberman's exploding capsules -> the Red Ribbon factory under Bay 9 -> Androids 13-15 ->
-- Bulma: Sixteen's parts, the air monitors, the drain gas -> Sixteen's birds -> Tongari Tower
-- (four ghost valves, Hatchiyack) -> Dr. Briefs' recording -> Somen -> King Kai -> the dance drills.
-- Every stage starts with a pursue or the trip to West Capital, so `fus start` picks up where it stopped.
fus = fus or {}
local F = fus

F.attack    = F.attack or "k"      -- "<attack> <keyword>" on quest enemies
F.benchWait = F.benchWait or 185   -- seconds Bulma needs at her bench ("three minutes")
F.otherworld = F.otherworld or "recall;fly;fly"  -- King Kai's planet, then up above it, for the survey
F.stage     = F.stage or "case"
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/fusionquest.lua"

local function info(color, msg) cecho("\n<" .. color .. ">[fus] " .. msg .. "\n") end
local function save()
  if type(table.save) == "function" then
    pcall(table.save, FILE, { attack = F.attack, stage = F.stage, benchWait = F.benchWait, otherworld = F.otherworld })
  end
end
do
  local t = {}
  if type(table.load) == "function" and io.open(FILE) then pcall(table.load, FILE, t) end
  for _, k in ipairs({ "attack", "stage", "benchWait", "otherworld" }) do if t[k] then F[k] = t[k] end end
end

-- ---------------------------------------------------------------- step builders
local function walk(list)   -- { "w", "Room", "w", "Room", ... }
  local out = {}
  for i = 1, #list, 2 do out[#out + 1] = { go = list[i], room = list[i + 1] } end
  return out
end
local function rep(dir, room, n)
  local out = {}
  for _ = 1, n do out[#out + 1] = dir; out[#out + 1] = room end
  return out
end
local function cat(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    if t.go or t.cmd or t.pursue or t.fight or t.wait or t.travel or t.special or t.delay then out[#out + 1] = t
    else for _, s in ipairs(t) do out[#out + 1] = s end end
  end
  return out
end
local function cmd(c, ok, extra)
  local s = { cmd = c, ok = type(ok) == "table" and ok or { ok } }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function pursue(who, extra) local s = { pursue = who }; for k, v in pairs(extra or {}) do s[k] = v end; return s end
local function fight(kw, dead, timeout) return { fight = kw, dead = dead, timeout = timeout or 300 } end
local function seen(text, timeout) return { wait = text, timeout = timeout or 15 } end
local function concat(...)
  local out = {}
  for _, t in ipairs({ ... }) do for _, x in ipairs(t) do out[#out + 1] = x end end
  return out
end

-- ---------------------------------------------------------------- the routes (from the game logs)
local GATE_TO_MARKET = { "w", "Eastside Avenue at the Gate", "w", "Market Stairs Lane", "w", "Top of the Market Stairs",
  "d", "Bottom of the Market Stairs", "w", "Lantern Lane", "w", "Market Square", "w", "Market Square Garden" }
local GATE_TO_BAY9 = { "w", "Eastside Avenue at the Gate", "s", "Eastside Avenue", "s", "Eastside Avenue",
  "w", "Eastside Avenue", "s", "Eastside Avenue", "s", "Eastside Avenue", "s", "University Boulevard",
  "e", "Warehouse Row", "e", "Warehouse Row", "e", "Warehouse Row", "e", "Loading Yard", "e", "Warehouse Bay 9" }
local GATE_TO_GENERATOR = { "w", "Eastside Avenue at the Gate", "n", "Eastside Avenue", "n", "Eastside Avenue",
  "e", "Back Alley", "n", "Back Alley", "n", "Alley by the Manhole", "d", "Below the Manhole",
  "e", "Storm Drain", "e", "Storm Drain", "e", "Storm Drain Junction", "e", "Storm Drain", "e", "Storm Drain",
  "s", "Overflow Weir", "s", "Settling Basin", "e", "Settling Basin", "e", "Generator Chamber" }
-- Dr. Briefs' Laboratory -> Plaza Fountain (west gallery, concourse, front gate, Capsule Corp Avenue)
local LAB_TO_FOUNTAIN = concat(rep("e", "Capsule Corp West Gallery", 6), { "e", "Concourse Lift Lobby",
  "s", "Concourse, West Arc", "s", "Concourse, West Arc", "s", "Concourse, South Arc" },
  rep("e", "Concourse, South Arc", 3), rep("n", "Concourse, East Arc", 3),
  { "e", "Capsule Corp Front Gate" }, rep("e", "Capsule Corp Avenue", 2), { "e", "Plaza Fountain" })
-- Plaza Fountain -> Dream Land's fountain plaza (east to the gate, up the sky lift)
local FOUNTAIN_TO_DREAMLAND = concat(rep("e", "Capsule Corp Avenue", 3), { "e", "Westside and Capsule Corp Avenue" },
  rep("e", "Dream Land Parkway", 5), { "e", "Dream Land Gate" }, rep("u", "Sky Lift", 4), { "u", "Dream Land Fountain Plaza" })
local DREAMLAND_TO_HOSPITAL = concat(rep("d", "Sky Lift", 4), { "d", "Dream Land Gate" },
  rep("w", "Dream Land Parkway", 5), { "w", "Westside and Capsule Corp Avenue",
  "n", "Westside Avenue", "n", "Westside Avenue", "e", "Westside Avenue", "n", "Westside Avenue", "n", "Westside Avenue",
  "n", "Northgate Avenue" }, rep("e", "Northgate Avenue", 5),
  { "n", "Hospital Drive", "n", "Hospital Drive", "n", "Wukong Hospital Lobby", "n", "Outpatient Hall", "n", "Garden Court" })
local HOSPITAL_TO_QUAD = concat({ "s", "Outpatient Hall", "s", "Wukong Hospital Lobby", "s", "Hospital Drive",
  "s", "Hospital Drive", "s", "Northgate Avenue" }, rep("w", "Northgate Avenue", 5),
  { "s", "Westside Avenue", "s", "Westside Avenue", "s", "Westside Avenue", "w", "Westside Avenue", "s", "Westside Avenue",
    "s", "Westside and Capsule Corp Avenue", "s", "Westside Avenue", "s", "Westside Avenue", "e", "Westside Avenue",
    "s", "Westside Avenue", "s", "Westside Avenue", "s", "University Boulevard" }, rep("e", "University Boulevard", 5),
  { "s", "University Plaza", "s", "West University Gate", "s", "North Quad" })
local WORKSHOP_TO_NORTH_HALL = { "e", "Capsule Corp Residence Hall", "n", "Capsule Corp Residence Hall", "n", "Capsule Corp North Hall" }
F.ROUTES = { GATE_TO_MARKET = GATE_TO_MARKET, GATE_TO_BAY9 = GATE_TO_BAY9, GATE_TO_GENERATOR = GATE_TO_GENERATOR,
  LAB_TO_FOUNTAIN = LAB_TO_FOUNTAIN, FOUNTAIN_TO_DREAMLAND = FOUNTAIN_TO_DREAMLAND,
  DREAMLAND_TO_HOSPITAL = DREAMLAND_TO_HOSPITAL, HOSPITAL_TO_QUAD = HOSPITAL_TO_QUAD }

local CRATE = "You peel back a price sticker"
local FREE = "You snap the chain off the bench."
local PANEL = { "Four zeroes", "You punch in" }
local MONITOR = "You thumb the little screen awake."
local SEARCH = { "Under a tarp stamped with a red star", "You already found what was in this crate." }
local VALVE = { "The stairs up clear", "The way to the machine floor is open" }
local LISTEN = "Sixteen nods once"
local ACK_DRILL = { "First: ", "Next: " }

-- ---------------------------------------------------------------- the stages
F.STAGES = {
  { "case", "Chief Doberman's exploding capsules: take the case file", {
    { travel = "westcapital", unless = "West Capital" },
    pursue("doberman"),
    cmd("say case", "The chief hands you a thin case file.", { timeout = 25 }) } },
  { "crates", "Inspect the three crates in the Underground Market", cat(
    { travel = "westcapital" }, walk(GATE_TO_MARKET),
    walk({ "n", "Market Square", "n", "North Stalls" }), cmd("inspect crate", CRATE),
    walk({ "s", "Market Square", "s", "Market Square Garden", "w", "Market Square", "w", "Smugglers' Corner" }), cmd("inspect crate", CRATE),
    walk({ "e", "Market Square", "e", "Market Square Garden", "s", "Market Square", "s", "South Stalls" }),
    cmd("inspect crate", "The same red star, all three crates", { timeout = 10 })) },
  { "courier", "Up the market stairs: the courier", cat(
    walk({ "n", "Market Square", "n", "Market Square Garden", "e", "Market Square", "e", "Lantern Lane",
           "e", "Bottom of the Market Stairs", "u", "Top of the Market Stairs", "e", "Market Stairs Lane" }),
    fight("courier", "a nervous courier is dead!")) },
  { "factory", "Bay 9: the foreman, the lift, three engineers and three panels", cat(
    { travel = "westcapital" }, walk(GATE_TO_BAY9),
    { fight = "foreman", dead = "the Bay 9 foreman is dead!", spawn = "The Bay 9 foreman", timeout = 300 },
    walk({ "d", "Lift Bottom", "s", "Assembly Line B" }), cmd("free engineer", FREE),
    walk({ "e", "Assembly Line C" }), cmd("free engineer", FREE),
    walk({ "s", "Assembly Line C", "s", "Line C Control Booth" }), cmd("shut panel", PANEL),
    walk({ "n", "Assembly Line C", "w", "Assembly Line B", "s", "Line B Control Booth" }), cmd("shut panel", PANEL),
    walk({ "n", "Assembly Line B", "n", "Assembly Line B", "w", "Assembly Line A" }), cmd("free engineer", FREE),
    walk({ "s", "Assembly Line A", "s", "Line A Control Booth" }), cmd("shut panel", "All three lines are dead.", { timeout = 10 })) },
  { "androids", "The Core: pull the breaker, Androids 15, 14 and 13", cat(
    walk({ "n", "Assembly Line A", "e", "Assembly Line B", "s", "Line B Control Booth", "s", "Back Corridor",
           "s", "Core Antechamber", "s", "The Core" }),
    cmd("pull breaker", "hauls the main breaker down"),
    fight("android", "Super Android 13 is dead!", 600)) },
  { "doberman", "Report to Chief Doberman", {
    pursue("doberman"), seen("stamps your case file CLOSED", 20) } },
  { "bulma", "Bulma: ask about Sixteen and the air", {
    pursue("bulma"), cmd("say sixteen", "Three crates of his parts", { timeout = 20 }),
    cmd("say air", "Ask him about the air", { timeout = 20 }) } },
  { "air", "Dr. Briefs: read the four air monitors", cat(
    pursue("dr briefs"), cmd("say air", "Read each one and the numbers will come straight here.", { timeout = 30 }),
    walk(LAB_TO_FOUNTAIN), cmd("read monitor", MONITOR),
    walk(FOUNTAIN_TO_DREAMLAND), cmd("read monitor", MONITOR),
    walk(DREAMLAND_TO_HOSPITAL), cmd("read monitor", MONITOR),
    walk(HOSPITAL_TO_QUAD), cmd("read monitor", MONITOR)) },
  { "parts", "Search Bay 9's storage for Sixteen's three parts", cat(
    { travel = "westcapital" }, walk(GATE_TO_BAY9),
    walk({ "d", "Lift Bottom", "e", "Gallery Catwalk", "e", "Gallery Catwalk", "e", "Gallery Catwalk",
           "n", "Capsule Storage", "n", "Capsule Vault" }), cmd("search", SEARCH),
    walk({ "s", "Capsule Storage" }), cmd("search", SEARCH),
    walk({ "s", "Gallery Catwalk", "w", "Gallery Catwalk", "w", "Gallery Catwalk", "w", "Lift Bottom",
           "s", "Assembly Line B", "s", "Assembly Line B", "s", "Line B Control Booth", "s", "Back Corridor",
           "e", "Back Corridor", "e", "Boiler Room", "s", "Tool Crib" }), cmd("search", SEARCH)) },
  { "gas", "Bulma's mask, the drain under Eastside Avenue, the war drone, a sample", cat(
    pursue("bulma"), cmd("say gas", "pushes a mask capsule into your hands", { timeout = 25 }),
    { travel = "westcapital" }, walk(GATE_TO_GENERATOR),
    { fight = "drone", dead = "a Tuffle war drone is dead!", spawn = "war drone", timeout = 300 },
    cmd("collect sample", "You cap a vial"),
    pursue("bulma"), seen("Bulma takes the vial", 20)) },
  { "bench", "Wait for Bulma's bench: Sixteen wakes, Capsule 211", { { special = "bench" } } },
  { "birds", "Listen with Sixteen: the Briefs garden, the Plaza Garden, Dream Land", cat(
    pursue("bulma"), walk(WORKSHOP_TO_NORTH_HALL), walk(rep("w", "Capsule Corp North Hall", 4)),
    walk({ "n", "Briefs Family Garden" }), cmd("listen", LISTEN),
    pursue("dr briefs"), walk(LAB_TO_FOUNTAIN), walk({ "n", "West Capital Plaza", "e", "Plaza Garden" }), cmd("listen", LISTEN),
    walk({ "w", "West Capital Plaza", "s", "Plaza Fountain" }), walk(FOUNTAIN_TO_DREAMLAND),
    cmd("listen", "I remember where it is", { timeout = 15 })) },
  { "tower", "Tongari Tower: Capsule 211, four ghost valves, Hatchiyack", cat(
    pursue("raichi", { ok = { "Your path is blocked", "You have successfully tracked down Dr. Raichi" }, settle = 3 }),
    cmd("throw 211 n", "You thumb the button and throw"),
    { go = "n", room = "Tongari Tower Lobby", already = true },
    walk({ "u", "Tower Stairwell, First Floor", "e", "Gassed Offices", "n", "Upper Stairs, First Floor",
           "w", "Gassed Offices", "w", "Valve Room, First Floor" }),
    fight("turles", "Ghost Turles is dead!"), cmd("shut valve", VALVE),
    walk({ "e", "Gassed Offices", "e", "Upper Stairs, First Floor", "u", "Tower Stairwell, Second Floor",
           "s", "Records Stacks", "w", "Server Room", "w", "Valve Room, Second Floor" }),
    fight("slug", "Ghost Lord Slug is dead!"), cmd("shut valve", VALVE),
    walk({ "e", "Server Room", "e", "Records Stacks", "n", "Tower Stairwell, Second Floor", "w", "Records Stacks",
           "w", "Upper Stairs, Second Floor", "u", "Tower Stairwell, Third Floor", "e", "Executive Hall",
           "s", "Valve Room, Third Floor" }),
    fight("cooler", "Ghost Cooler is dead!"), cmd("shut valve", VALVE),
    walk({ "n", "Executive Hall", "e", "Upper Stairs, Third Floor", "u", "Tower Stairwell, Fourth Floor",
           "w", "Tank Farm", "s", "Valve Room, Fourth Floor" }),
    fight("frieza", "Ghost Frieza is dead!"), cmd("shut valve", VALVE),
    walk({ "n", "Tank Farm", "w", "Upper Stairs, Fourth Floor", "u", "Machine Floor Landing",
           "e", "Destron Control Gallery", "s", "The Machine Floor" }),
    fight("hatchiyack", "Full Power Hatchiyack is dead!", 900)) },
  { "report", "Tell Bulma about the tower", cat(
    pursue("bulma"), walk({ "e", "Capsule Corp Residence Hall", "w", "Bulma's Workshop" }),
    seen("Dad's Blueprint Archive, through the west gallery", 20)) },
  { "archive", "Dr. Briefs' Blueprint Archive: watch Goku's recording", cat(
    pursue("dr briefs"), walk({ "e", "Capsule Corp West Gallery", "n", "Blueprint Archive" }),
    cmd("watch", "A small capsule earpiece is taped under the screen", { timeout = 20 })) },
  { "somen", "Somen at the Otherworld Tournament Arena", {
    { travel = "otherworld" }, seen("The steps are easy", 20) } },
  { "kaikai", "King Kai: laugh at the joke, then the first dance", {
    { go = "recall", room = "King Kai's Planet" }, pursue("king"), { special = "kaikai" } } },
  { "gravity", "The gravity room drill", {
    { travel = "westcapital" }, pursue("vegeta"), { go = "e", room = "Gravity Room South" },
    { special = "drill", done = "Now the hangar" } } },
  { "hangar", "The hangar drill, opposite Sixteen", cat(
    pursue("bulma"), walk(WORKSHOP_TO_NORTH_HALL), walk(rep("e", "Capsule Corp North Hall", 4)),
    walk({ "n", "Capsule Corp Hangar" }), { special = "drill", done = "That is it. That is the dance." }) },
  { "done", "Fuse with another player (10 billion base PL, knows the dance), then walk into Bulma's workshop fused", {} },
}
local INDEX = {}
for i, s in ipairs(F.STAGES) do INDEX[s[1]] = i end

-- ---------------------------------------------------------------- what the game is showing
local run = {}
local here = { room = nil, prev = nil, combat = false, target = false }
F.here = here

local function setTimer(secs, fn)
  if run.timer then killTimer(run.timer) end
  run.timer = tempTimer(secs, function() run.timer = nil; if run.active then fn() end end)
end
local function stopTimer() if run.timer then killTimer(run.timer); run.timer = nil end end

function F.stop(quiet)
  local was = run.active
  stopTimer(); run = {}
  if was and not quiet then info("yellow", "Stopped (stage " .. F.stage .. "; `fus start` carries on)") end
end
local function fail(msg) local st = F.stage; F.stop(true); info("red", msg .. " - stopped at stage " .. st .. " (`fus start` tries it again)") end

local function matchAny(l, list)
  if type(list) == "string" then list = { list } end
  for _, p in ipairs(list or {}) do if l:find(p, 1, true) then return p end end
end

local nextStep, startStage

-- wait for a line (handler returns true when the step is done); lines since the step began count too
local function waitFor(what, secs, handler, onTimeout)
  run.handler = handler
  run.waiting = what
  for i = run.mark or 1, #run.lines do
    if run.handler ~= handler then return end
    if handler(run.lines[i]) then return end
  end
  setTimer(secs, onTimeout or function() fail("Timed out waiting for " .. what) end)
end
local function done() run.handler = nil; stopTimer(); nextStep() end

-- ---------------------------------------------------------------- travel
local TRAVEL = {
  westcapital = { area = "West Capital", first = { "recall", "press button", "s", "s", "enter vortex" }, ready = "You step through the portal." },
  otherworld = { area = "Otherworld Tournament Arena", ready = "You fly up high above the area!" },
}
local function travel(where)
  local t = TRAVEL[where]
  local cmds = t.first or {}
  if where == "otherworld" then cmds = {}; for c in F.otherworld:gmatch("[^;]+") do cmds[#cmds + 1] = c end end
  for _, c in ipairs(cmds) do send(c) end
  local function survey()
    send("survey")
    waitFor(t.area .. " in the survey", 15, function(l)
      local n, a = l:match("^%s*(%d+)%. (.-), go %a+")
      if a ~= t.area then return end
      send("survey " .. n .. " fly")
      waitFor("the flight to " .. t.area, 180, function(x)
        if x:find("You land on the ground in front of " .. t.area, 1, true) then
          send("enter")
          if where == "westcapital" then
            -- done on the prompt after the gate, once its own lines are in
            local at = false
            waitFor("West Capital Gate", 15, function(y)
              if y == "West Capital Gate" then at = true end
              if at and y:find("^%[Pl: ") then done(); return true end
            end)
          else done() end
          return true
        end
      end)
      return true
    end)
  end
  waitFor(where, where == "otherworld" and 15 or 60,
          function(l) if l:find(t.ready, 1, true) then survey(); return true end end,
          where == "otherworld" and survey or nil)
end

-- ---------------------------------------------------------------- specials
local SPECIAL = {}

-- Bulma's bench: wait, walk out and back in, until Capsule 211 is handed over
function SPECIAL.bench()
  run.tries = (run.tries or 0) + 1
  if run.tries > 5 then return fail("Bulma never handed over Capsule 211") end
  info("white", "Bulma's bench: back in " .. F.benchWait .. "s (try " .. run.tries .. ")")
  setTimer(F.benchWait, function()
    send("e"); send("w")
    run.mark = #run.lines + 1
    waitFor("Bulma", 20, function(l)
      if l:find("Bulma holds up a capsule with 211", 1, true) then done(); return true end
      if l:find("Walk back in in about", 1, true) then SPECIAL.bench(); return true end
    end, SPECIAL.bench)
  end)
end

-- the calls the drills give: "6 calls, 4 seconds each. First: point" then "Next: swing" ...
local function drillLine(l, finished)
  local call = l:match("First: (.+)$") or l:match("^Next: (.+)$")
  if call then send(call) return false end
  if finished and l:find(finished, 1, true) then return true end
  if l:find("Fuuu... sion... HA!", 1, true) and not finished then return true end
end

function SPECIAL.drill(step)
  send("drill")
  waitFor("the drill", 120, function(l)
    if drillLine(l, step.done) then done(); return true end
    if l:find("There is nothing here you can drill.", 1, true) then fail("No drill console in this room"); return true end
  end)
end

-- King Kai: the joke (laugh), walk out and back in, then "do it back to me in order"
function SPECIAL.kaikai()
  waitFor("King Kai", 60, function(l)
    if l:find("Go on. Laugh.", 1, true) then send("laugh"); return false end
    if l:find("Walk out and back in when you are ready", 1, true) then send("s"); send("n"); return false end
    local list = l:match("do it back to me in order, [^:]*: (.-)%. Go!")
    if list then
      local calls = {}
      for c in list:gmatch("[^,]+") do calls[#calls + 1] = c:match("^%s*(.-)%s*$") end
      for i, c in ipairs(calls) do tempTimer(i * 1.5, function() if run.active then send(c) end end) end
      return false
    end
    if l:find("Fuuu... sion... HA!", 1, true) then done(); return true end
  end)
end

-- ---------------------------------------------------------------- one step
local function runStep(s)
  -- a wait or special also sees what the step before it brought in (NPCs talk before "tracked down")
  if not (s.wait or s.special) then run.mark = #run.lines + 1 end
  run.arrived, run.atRoom = nil, nil
  if s.travel then
    if s.unless and here.area == s.unless then return nextStep() end
    return travel(s.travel)
  elseif s.go then
    if s.already and here.room == s.room then return nextStep() end
    send(s.go)
    waitFor(s.room, 20, function(l)
      if l == "Alas, you cannot go that way..." then
        if s.already then nextStep() else fail("Can't go " .. s.go .. " towards " .. s.room) end
        return true
      end
      if run.arrived then
        local a = run.arrived; run.arrived = nil
        if a ~= s.room then fail("Went " .. s.go .. " expecting " .. s.room .. " but got " .. a); return true end
        run.atRoom = true
      end
      if run.atRoom and l:find("^%[Pl: ") then run.atRoom = nil; done(); return true end
    end)
  elseif s.cmd then
    send(s.cmd)
    waitFor("'" .. s.cmd .. "'", s.timeout or 15, function(l)
      if matchAny(l, s.ok) then done(); return true end
      if l:find(" is not here%.$") or l:find("^There is nothing here") then fail("'" .. s.cmd .. "' here: " .. l); return true end
    end)
  elseif s.pursue then
    send("pursue " .. s.pursue)
    local ok = s.ok or { "You have successfully tracked down", "You're already in the same room!!" }
    waitFor("pursue " .. s.pursue, 120, function(l)
      if matchAny(l, ok) then
        if s.settle then run.handler = nil; setTimer(s.settle, done) else done() end
        return true
      end
      if l:find("can't seem to sense", 1, true) or l == "You sense no ki." then
        fail("Can't find " .. s.pursue .. " from here"); return true
      end
    end)
  elseif s.fight then
    if s.spawn then
      local present = false
      for i = math.max(1, #run.lines - 40), #run.lines do if run.lines[i]:find(s.spawn, 1, true) then present = true end end
      if not present then return nextStep() end
    end
    send(F.attack .. " " .. s.fight)
    run.attacks = 1
    waitFor(s.dead, s.timeout, function(l)
      if l:find(s.dead, 1, true) then setTimer(2, done); run.handler = nil; return true end
      -- a prompt with no target: the fight stopped (or the next one hasn't started) - hit again
      if l:find("^%[Pl: ") and not here.combat and run.attacks < 12 then
        run.attacks = run.attacks + 1
        send(F.attack .. " " .. s.fight)
      end
    end)
  elseif s.wait then
    waitFor(s.wait, s.timeout, function(l) if l:find(s.wait, 1, true) then done(); return true end end)
  elseif s.special then
    SPECIAL[s.special](s)
  elseif s.delay then
    setTimer(s.delay, nextStep)
  end
end

nextStep = function()
  if not run.active then return end
  run.i = run.i + 1
  local s = run.steps[run.i]
  if not s then
    local i = INDEX[F.stage]
    local nxt = F.STAGES[i + 1]
    info("green", "Stage done: " .. F.stage .. (nxt and (" -> " .. nxt[1]) or ""))
    if not nxt then return F.stop(true) end
    F.stage = nxt[1]; save()
    return startStage()
  end
  -- never walk or act in the middle of a fight
  if here.combat and not s.fight then
    run.handler = function(l) if l:find("^%[Pl: ") and not here.combat then run.handler = nil; runStep(s); return true end end
    return
  end
  runStep(s)
end

startStage = function()
  local st = F.STAGES[INDEX[F.stage]]
  run.steps, run.i = st[3], 0
  if #run.steps == 0 then
    info("green", st[2])
    return F.stop(true)
  end
  info("white", "Stage " .. F.stage .. ": " .. st[2])
  nextStep()
end

function F.start()
  F.stop(true)
  run = { active = true, lines = {} }
  startStage()
end

-- ---------------------------------------------------------------- every line
local WEST_CAPITAL = { ["West Capital Gate"] = true }
function F.line(l)
  if type(l) ~= "string" then return end
  -- the room title is the line just before "Status:  ..."
  if l:find("^Status:  ") and here.prev then
    here.room = here.prev
    if WEST_CAPITAL[here.room] then here.area = "West Capital" end
    if here.room == "King Kai's Planet" then here.area = nil end
    if run.active then run.arrived = here.room end
  elseif l:find("^%[Time: ") then here.target = false
  elseif l:find("^%[Target: ") then here.target = true
  elseif l:find("^%[Pl: ") then here.combat = here.target end
  if l:find("You step through the portal.", 1, true) or l:find("You press the Zeno Button", 1, true) then here.area = nil end
  here.prev = l
  if not run.active then return end
  local lines = run.lines
  lines[#lines + 1] = l
  if #lines > 400 then table.remove(lines, 1); run.mark = math.max(1, (run.mark or 1) - 1) end
  if run.handler and run.handler(l) then return end
end

-- ---------------------------------------------------------------- `fus` alias
F.HELP = {
  { "fus start",          "Carry on from the current stage (it's saved)" },
  { "fus status",         "The current stage" },
  { "fus stages",         "Every stage, in order" },
  { "fus stage <name>",   "Jump to a stage" },
  { "fus attack <cmd>",   "Attack used on quest enemies (now: " .. F.attack .. ")" },
  { "fus otherworld <c>", "Commands to get above King Kai's planet for the survey (now: " .. F.otherworld .. ")" },
  { "fus stop",           "Stop" },
  { "fus update",         "Update FusionQuest to the latest release" },
}
function F.help()
  cecho("\n<cyan>The West Capital fusion questline (fus):\n")
  for _, h in ipairs(F.HELP) do cecho(string.format("  <yellow>%-22s<white>%s\n", h[1], h[2])) end
end

function F.command(c, arg)
  if c == "start" or c == "go" then F.start()
  elseif c == "status" then info("white", "Stage " .. F.stage .. ": " .. F.STAGES[INDEX[F.stage]][2] .. (run.active and " (running)" or ""))
  elseif c == "stages" then
    for _, s in ipairs(F.STAGES) do cecho(string.format("  <%s>%-10s<white>%s\n", s[1] == F.stage and "green" or "yellow", s[1], s[2])) end
  elseif c == "stage" and arg then
    if not INDEX[arg] then return info("red", "No stage '" .. arg .. "': see `fus stages`") end
    F.stop(true); F.stage = arg; save(); info("white", "Stage set to " .. arg .. ": `fus start` to run it")
  elseif c == "attack" and arg then F.attack = arg; F.HELP[5][2] = "Attack used on quest enemies (now: " .. arg .. ")"; save(); info("white", "Attack: " .. arg)
  elseif c == "otherworld" and arg then F.otherworld = arg; save(); info("white", "Otherworld: " .. arg)
  elseif c == "stop" then F.stop()
  else F.help() end
end
