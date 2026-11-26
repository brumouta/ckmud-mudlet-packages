-- Cumber: Chief Rusk's containment assignment on the Prison Planet. Type `cumber help`.
-- Pursues Rusk, takes the assignment, studies the records, reads the west and east service plates,
-- inspects the cooling loop and vents the coupler, then solves the three load cards at the
-- restraint workshop rig and hands the coupler back to Rusk (500,000 zenni and 40 tokens).
cumber = cumber or {}
local C = cumber

C.attack = C.attack or "de"   -- used on rivals that jump you
C.travel = C.travel or "crecall;leave"  -- gets you into space before `pursue rusk` (`cumber travel`)
C.per    = C.per or { west = 2, east = 3 }  -- load units per notch; the plates say so, and are re-read
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/cumber.lua"

local function info(color, msg) cecho("\n<" .. color .. ">[cumber] " .. msg .. "\n") end
local function save()
  if type(table.save) == "function" then pcall(table.save, FILE, { attack = C.attack, travel = C.travel }) end
end
do
  local t = {}
  if type(table.load) == "function" and io.open(FILE) then pcall(table.load, FILE, t) end
  if t.attack then C.attack = t.attack end
  if t.travel then C.travel = t.travel end
end

local WORDS = { zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10 }

-- ---------------------------------------------------------------- the route
-- From Rusk (Guard Withdrawal Post) round the containment level and back.
-- go = a step and the room it reaches; cmd = sent here, done when a line starts with `ok`.
local PREP = {
  { go = "e", room = "Evacuation Stair" },
  { go = "d", room = "Evacuation Landing" },
  { go = "e", room = "Containment Records" },
  { cmd = "study containment", ok = "The failures share a mistake" },
  { go = "s", room = "Western Suppressor Chamber" },
  { go = "s", room = "Western Coil Access" },
  { cmd = "read west plate", ok = "The western service plate" },
  { go = "n", room = "Western Suppressor Chamber" },
  { go = "e", room = "Western Feed Gallery" },
  { go = "e", room = "Inner Guard Passage" },
  { go = "e", room = "Observation Stair" },
  { go = "e", room = "Eastern Coil Access" },
  { cmd = "read east plate", ok = "The eastern service plate" },
  { go = "n", room = "Eastern Suppressor Chamber" },
  { go = "w", room = "Eastern Feed Gallery" },
  { go = "w", room = "Coolant Return Chamber" },
  { go = "n", room = "Southern Cooling Walk" },
  { go = "n", room = "Cooling Pump Station" },
  { go = "w", room = "Northern Cooling Walk" },
  { cmd = "inspect cooling loop", ok = "The live cooling circuit" },
  { cmd = "vent coupler", ok = "You bleed the disconnected test hose" },
  { go = "w", room = "Restraint Workshop" },
}
-- Card 2 or 3 already on the coupler: the prep is done, go straight to the workshop
local TO_RIG = {
  { go = "e", room = "Evacuation Stair" },
  { go = "d", room = "Evacuation Landing" },
  { go = "e", room = "Containment Records" },
  { go = "n", room = "Suppressor Issue Room" },
  { go = "n", room = "Restraint Workshop" },
}
local TO_RUSK = {
  { go = "s", room = "Suppressor Issue Room" },
  { go = "s", room = "Containment Records" },
  { go = "w", room = "Evacuation Landing" },
  { go = "u", room = "Evacuation Stair" },
  { go = "w", room = "Guard Withdrawal Post" },
}
C.PREP, C.TO_RIG, C.TO_RUSK = PREP, TO_RIG, TO_RUSK

-- ---------------------------------------------------------------- the cards
-- "Card 1 calls for west 6 load units and east 12." -> west notch 3, east notch 4
function C.parseCard(l)
  local n, w, e = l:match("^Card (%d) calls for west (%d+) load units and east (%d+)")
  if n then return tonumber(n), tonumber(w), tonumber(e) end
end
function C.notches(w, e)
  local wn, en = w / C.per.west, e / C.per.east
  if wn % 1 ~= 0 or en % 1 ~= 0 or wn < 0 or wn > 5 or en < 0 or en > 5 then return end
  return math.floor(wn), math.floor(en)
end

-- ---------------------------------------------------------------- the run
local run = {}
local function setTimer(secs, fn)
  if run.timer then killTimer(run.timer) end
  run.timer = tempTimer(secs, function() run.timer = nil; if run.active then fn() end end)
end
local function stopTimer() if run.timer then killTimer(run.timer); run.timer = nil end end

function C.stop(quiet)
  local was = run.active
  stopTimer(); run = {}
  if was and not quiet then info("yellow", "Stopped") end
end
local function fail(msg) C.stop(true); info("red", msg .. " - stopped") end

local function waitFor(what, secs, handler, onTimeout)
  run.wait, run.handler = what, handler
  setTimer(secs, onTimeout or function() fail("Timed out waiting for " .. what) end)
end

local pursue, takeAssignment, checkCoupler, walk, rig, handIn

pursue = function()
  run.stage = "pursue"
  send("pursue rusk")
  waitFor("Chief Rusk", 120, function(l)
    if l == "You have successfully tracked down Chief Rusk!" or l == "You're already in the same room!!" then
      takeAssignment(); return true
    elseif l == "You sense no ki." then
      fail("Can't sense Rusk from here: check `cumber travel` (now: " .. (C.travel ~= "" and C.travel or "none") .. ")")
      return true
    end
  end)
end

takeAssignment = function()
  run.stage = "assignment"
  send("say containment")
  -- Rusk explains it all ("'Study containment' in the records room..."), or once you've had that,
  -- "Bring me a coupler that has passed all three cards..."; carry on either way
  waitFor("Rusk's instructions", 4, function(l)
    if l:find("^Chief Rusk says, ''Study containment'") or l:find("^Chief Rusk says, 'Bring me a coupler") then
      checkCoupler(); return true
    end
  end, function() checkCoupler() end)
end

-- `look testcoupler` says which card is up. Before the records are studied it says
-- "'Study containment' in the records room before interpreting a quiet coil." instead: do the prep.
checkCoupler = function()
  run.stage = "coupler"
  send("look testcoupler")
  waitFor("the test coupler", 4, function(l)
    local n = C.parseCard(l)
    if n then
      info("white", "Coupler on card " .. n)
      if n == 1 then walk(PREP, rig) else walk(TO_RIG, rig) end
      return true
    end
    if l:find("^'Study containment' in the records room") then walk(PREP, rig); return true end
  end, function() walk(PREP, rig) end)
end

walk = function(route, done, from)
  run.stage, run.route, run.step, run.done = "walk", route, from or 0, done
  local function nextStep()
    run.step = run.step + 1
    local s = route[run.step]
    if not s then return done() end
    if s.go then
      send(s.go)
      waitFor(s.room, 15, function(l)
        if l == s.room then nextStep(); return true end
        if l == "Alas, you cannot go that way..." then
          fail("Couldn't go " .. s.go .. " towards " .. s.room); return true
        end
      end)
    else
      send(s.cmd)
      waitFor("'" .. s.cmd .. "'", 15, function(l)
        if l:find(s.ok, 1, true) == 1 then
          local side, word = l:match("each (%a+) notch supplies (%a+) load units")
          if side and C.per[side] and WORDS[word] then C.per[side] = WORDS[word] end
          nextStep(); return true
        end
        if l:find(" not here%.$") then fail("'" .. s.cmd .. "' isn't done here: " .. l); return true end
      end)
    end
  end
  nextStep()
end

rig = function()
  run.stage, run.failures = "rig", run.failures or 0
  send("look testcoupler")
  waitFor("the card", 10, function(l)
    local n, w, e = C.parseCard(l)
    if not n then return end
    local wn, en = C.notches(w, e)
    if not wn then
      fail(string.format("Card %d (west %d, east %d) doesn't fit %d/%d units per notch", n, w, e, C.per.west, C.per.east))
      return true
    end
    run.card = n
    info("white", string.format("Card %d: west %d units = notch %d, east %d units = notch %d", n, w, wn, e, en))
    send("calibrate west " .. wn)
    send("calibrate east " .. en)
    send("loadtest coupler")
    waitFor("the load test", 15, function(t)
      if t:find("^Both measured loads match card") then rig(); return true end
      if t:find("^The third load card holds") then info("green", "All three cards passed"); walk(TO_RUSK, handIn); return true end
      if t:find("^The rig reads west") or t:find("^Set both dials deliberately") then
        run.failures = run.failures + 1
        if run.failures > 3 then fail("The load test keeps failing: " .. t); return true end
        info("yellow", "Load test failed, trying again: " .. t)
        setTimer(1, rig)
        return true
      end
    end)
    return true
  end)
end

handIn = function()
  run.stage = "handin"
  send("say coupler")
  waitFor("Rusk's reward", 10, function(l)
    if l:find("^Chief Rusk says, 'Three load records") then
      C.stop(true)
      info("green", "Containment assignment done: Rusk pays 500,000 zenni and 40 tokens")
      return true
    end
  end)
end

function C.start()
  C.stop(true)
  run = { active = true }
  info("green", "Containment assignment: off to Chief Rusk")
  if C.travel == "" then return pursue() end
  run.stage = "travel"
  for c in C.travel:gmatch("[^;]+") do send(c) end
  -- `leave` from the clan hall shows the space room, ending "You can 'land' here."
  -- ("You fly up into the air." first when you weren't flying)
  waitFor("space", 10, function(l)
    if l == "You can 'land' here." then setTimer(1, pursue); return true end
  end, pursue)
end

-- A rival jumps you: fight back, then start that step again
function C.rival(name)
  if run.rival then return end
  run.rival = { name = name, stage = run.stage }
  stopTimer()
  info("yellow", "Rival: " .. name .. " - fighting back")
  send(C.attack .. " " .. name:match("^(%S+)"):lower())
  run.wait, run.handler = name .. " to die", nil
  setTimer(300, function() fail("The fight with " .. name .. " is taking too long") end)
end

-- ---------------------------------------------------------------- every line
function C.line(l)
  if not run.active or type(l) ~= "string" then return end
  local rival = l:match("^(.-) flies out of nowhere and attacks you!")
  if rival then return C.rival(rival) end
  if run.rival then
    if l == run.rival.name .. " is dead!  R.I.P." or l:find(run.rival.name .. " is dead!", 1, true) == 1 then
      local stage = run.rival.stage
      run.rival = nil
      info("green", "Rival down")
      -- a pursue that was cut off is redone; on the walk the current step is resent
      setTimer(2, function()
        if stage == "pursue" then pursue()
        elseif stage == "walk" then walk(run.route, run.done, run.step - 1)
        elseif stage == "rig" then rig()
        elseif stage == "handin" then handIn()
        elseif stage == "travel" then C.start()
        else takeAssignment() end
      end)
    end
    return
  end
  if run.handler and run.handler(l) then return end
end

-- ---------------------------------------------------------------- `cumber` alias
C.HELP = {
  { "cumber start",          "Do Chief Rusk's containment assignment on the Prison Planet, start to finish" },
  { "cumber travel <cmds>",  "Gets you to space before `pursue rusk`, ;-separated (now: " .. (C.travel ~= "" and C.travel or "none") .. "; `off` skips it)" },
  { "cumber attack <cmd>",   "Attack used on rivals (now: " .. C.attack .. ")" },
  { "cumber solve",          "At the workshop rig: just solve the cards" },
  { "cumber stop",           "Stop" },
  { "cumber update",         "Update Cumber to the latest release" },
}
function C.help()
  cecho("\n<cyan>Cumber's containment assignment (cumber):\n")
  for _, h in ipairs(C.HELP) do cecho(string.format("  <yellow>%-22s<white>%s\n", h[1], h[2])) end
end

function C.command(c, arg)
  if c == "start" or c == "go" then C.start()
  elseif c == "solve" then C.stop(true); run = { active = true }; rig()
  elseif c == "travel" and arg then
    C.travel = (arg == "off" or arg == "none") and "" or arg
    C.HELP[2][2] = "Gets you to space before `pursue rusk`, ;-separated (now: " .. (C.travel ~= "" and C.travel or "none") .. ")"
    save(); info("white", "Travel: " .. (C.travel ~= "" and C.travel or "none"))
  elseif c == "attack" and arg then C.attack = arg; save(); info("white", "Attack: " .. arg)
  elseif c == "stop" then C.stop()
  else C.help() end
end
