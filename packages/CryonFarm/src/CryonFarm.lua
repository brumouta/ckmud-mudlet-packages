-- Farms the Confession of Cryon Frigidus (Zero Nexus hidden lab, Iceria). Type `cryon help`.
--
-- One run: `it innkeeper`, walk to the Research Facility and its dead-end Atrium (the access card
-- opens the Hidden Hallway), through the lab ring to the Incubation Chamber's trapdoor, down to the
-- Control Room, then the four chambers around it:
--   Pyrokinetic (NE)      extract, then out before the Fire Fields burn you
--   Electromagnetic (SE)  kill the four Electromagnetic Fields round the centre, then extract
--   Cryogenic (SW)        extract (it frees the citizen first)
--   Genetic (NW)          wait for "How..did...I..get here?", say kidnapped, smack citizen
-- and Cryon Frigidus hands over the confession.
cryon = cryon or {}
local C = cryon

-- ---------------------------------------------------------------- settings
C.attack = C.attack or "fg f"        -- kills an Electromagnetic Field (the Elite that charges in dies to auto-combat)
C.stepTimeout = C.stepTimeout or 8   -- seconds to wait for each room
C.fightTimeout = C.fightTimeout or 90
C.runs = C.runs or 0                 -- confessions this session

local function info(color, msg) cecho("\n<" .. color .. ">[cryon] " .. msg .. "\n") end

-- ---------------------------------------------------------------- the route
local function moves(list)
  local out = {}
  for _, m in ipairs(list) do out[#out + 1] = { dir = m[1], title = m[2] } end
  return out
end
local CW, FP, RA, HH, HL = "Commerce Way", "Frost Plaza", "Research Facility Atrium", "Hidden Hallway", "Hidden Laboratory"
local HI, PC, EC, CC, GC = "Hallway Intersection", "Pyrokinetic Mutation Chamber", "Electromagnetic Mutation Chamber",
  "Cryogenic Mutation Chamber", "Genetic Amplification Chamber"

C.ROUTE = {}
local function add(step) C.ROUTE[#C.ROUTE + 1] = step end
local function walk(list) for _, m in ipairs(moves(list)) do add(m) end end

add({ send = "it innkeeper", title = "Blizzards Edge Inn", label = "the Inn" })
walk({ { "s", CW }, { "e", CW }, { "e", CW }, { "s", CW }, { "s", CW }, { "e", CW }, { "e", CW }, { "e", FP }, { "e", FP },
       { "n", "snow covered path" }, { "n", "Zero Nexus Research Facility" }, { "n", RA }, { "n", RA }, { "n", RA }, { "n", RA } })
add({ title = HH, label = "the access card opens the Hidden Hallway" })        -- no command: it moves you
walk({ { "e", HH }, { "e", HH }, { "e", HH }, { "e", HL }, { "s", HL }, { "s", HL }, { "e", HL }, { "e", HL }, { "e", HL },
       { "n", HL }, { "n", HL }, { "e", "Incubation Chamber" } })
add({ title = HL, label = "the trapdoor drops you into the lower lab" })       -- no command: the trapdoor
walk({ { "e", HL }, { "e", HL }, { "e", HL }, { "e", HL }, { "d", "Control Room" } })
-- Pyrokinetic: up the north hallway, east into the chamber, the citizen is in the centre
walk({ { "n", "Hallway" }, { "n", "Hallway" }, { "n", HI }, { "e", "Entrance to the " .. PC }, { "e", PC }, { "e", PC } })
add({ extract = true, label = "Pyrokinetic sample" })
-- out south, down the east side into the Electromagnetic chamber
walk({ { "s", PC }, { "s", "Entrance to the " .. PC }, { "s", HI }, { "s", "Entrance to the " .. EC }, { "s", EC } })
add({ field = true })
walk({ { "e", EC }, { "s", EC } })
add({ field = true })
walk({ { "s", EC }, { "w", EC } })
add({ field = true })
walk({ { "w", EC }, { "n", EC } })
add({ field = true })
walk({ { "e", EC } })
add({ extract = true, label = "Electromagnetic sample" })
-- west along the south side into the Cryogenic chamber
walk({ { "w", EC }, { "w", "Entrance to the " .. EC }, { "w", HI }, { "w", "Entrance to the " .. CC }, { "w", CC }, { "w", CC } })
add({ extract = true, label = "Cryogenic sample" })
-- north up the west side into the Genetic Amplification chamber
walk({ { "n", CC }, { "n", "Entrance to the " .. CC }, { "n", HI }, { "n", "Entrance to the " .. GC }, { "n", GC }, { "n", GC } })
add({ genetic = true, label = "the last citizen and the confession" })

-- ---------------------------------------------------------------- state
C.active = false
C.step = C.step or 1
C.left = C.left or 0         -- runs still to do after this one
C.gen = C.gen or 0

-- ---------------------------------------------------------------- waiting
local W
local function clearWait()
  if W and W.timer then killTimer(W.timer) end
  W = nil
end
local function expect(pats, timeout, cb)
  clearWait()
  local w = { pats = pats, cb = cb }
  W = w
  w.timer = tempTimer(timeout, function() if W == w then W = nil; cb("timeout") end end)
end
local function check(s, signal)
  if not W then return end
  for _, p in ipairs(W.pats) do
    local hit
    if signal then hit = p[1] == "@" .. s else hit = p[1]:sub(1, 1) ~= "@" and s:find(p[1], 1, p.plain) end
    if hit then
      local w = W
      clearWait()
      return w.cb(p[2])
    end
  end
end
local function later(delay, fn)
  local gen = C.gen
  tempTimer(delay, function() if C.active and C.gen == gen then fn() end end)
end

-- ---------------------------------------------------------------- reading the game
local prev
function C.line(l)
  l = l:gsub("%s+$", "")
  -- a room: its title is the line before "Status:"
  if l:find("^Status:  ") and prev and prev ~= "" then
    C.room = prev:gsub("^%s+", "")
    C.fieldHere = false
    tempTimer(0.3, function() check("room", true) end)
  end
  if l:find("^An Electromagnetic Field is blocking the path") then C.fieldHere = true end
  if l:find("gives you Confession of Cryon Frigidus") then C.got = true end
  prev = l
  check(l)
end

-- ---------------------------------------------------------------- running the route
local function stop(why, color)
  C.active = false
  C.gen = C.gen + 1
  clearWait()
  info(color or "red", why .. (C.step <= #C.ROUTE and (" (at step " .. C.step .. ")") or ""))
end

local BLOCKED = "^Alas, you cannot go that way"

local nextStep
local function arrive(step)
  local pats = { { "@room", "room" }, { BLOCKED, "blocked" }, { "^You can't do that while fighting", "fighting" },
                 { "^You are fighting", "fighting" } }
  expect(pats, C.stepTimeout, function(k)
    if k == "room" and C.room == step.title then return nextStep() end
    if k == "room" then return stop("Expected " .. step.title .. " but ended up in " .. tostring(C.room)) end
    stop("Couldn't reach " .. step.title .. " (" .. k .. ")")
  end)
end

local function runStep(step)
  if step.label then info("cyan", step.label) end
  if step.send then send(step.send, false); return arrive(step) end
  if step.dir then send(step.dir, false); return arrive(step) end
  if step.title then return arrive(step) end

  if step.field then
    if not C.fieldHere then return nextStep() end
    send(C.attack, false)
    return expect({ { "Electromagnetic Field blocking the path to the Kidnapped Icerian Citizen weakens", "ok" },
                    { "Electromagnetic Field blocking the path to the Kidnapped Icerian Citizen shatters", "ok" } },
      C.fightTimeout, function(k)
        if k ~= "ok" then return stop("The Electromagnetic Field didn't go down (is `cryon attack` right? now: " .. C.attack .. ")") end
        later(1.5, nextStep)    -- let the round finish before moving
      end)
  end

  if step.extract then
    send("extract", false)
    return expect({ { "collects a sample", "ok" } }, 30, function(k)
      if k ~= "ok" then return stop("No sample collected") end
      later(0.5, nextStep)
    end)
  end

  if step.genetic then
    C.got = false
    return expect({ { "How..did...I..get here?", "ask", plain = true } }, 60, function(k)
      if k ~= "ask" then return stop("The last citizen never asked how he got here") end
      send("say kidnapped", false)
      expect({ { "begins to pass out", "smack" } }, 60, function(k2)
        if k2 ~= "smack" then return stop("The citizen never passed out") end
        send("smack citizen", false)
        expect({ { "gives you Confession of Cryon Frigidus", "ok" } }, 15, function(k3)
          if k3 ~= "ok" then return stop("No confession after the smack") end
          later(1, nextStep)
        end)
      end)
    end)
  end
end

nextStep = function()
  if not C.active then return end
  C.step = C.step + 1
  local step = C.ROUTE[C.step]
  if step then return runStep(step) end
  C.runs = C.runs + 1
  if C.left > 0 then
    C.left = C.left - 1
    info("green", ("Confession #%d. %d more to go"):format(C.runs, C.left + 1))
    C.step = 0
    return later(2, nextStep)
  end
  C.active = false
  info("green", ("Confession #%d. Done"):format(C.runs))
end

function C.start(times, from)
  if C.active then return info("yellow", "Already running (cryon stop to stop)") end
  C.left = math.max((times or 1) - 1, 0)
  C.active = true
  C.gen = C.gen + 1
  C.step = (from or 1) - 1
  info("green", "Farming the confession" .. (times and times > 1 and (" x" .. times) or "") .. ". cryon stop stops")
  nextStep()
end

function C.stop() if C.active then stop("Stopped", "yellow") else info("white", "Not running") end end

-- ---------------------------------------------------------------- `cryon` alias
C.HELP = {
  { "cryon start [n]",      "From anywhere: it innkeeper, walk to the lab, take the four samples, get the confession (n times)" },
  { "cryon stop",           "Stop" },
  { "cryon resume",         "Carry on from where it stopped (fix things by hand first, then resume)" },
  { "cryon attack <cmd>",   "What kills an Electromagnetic Field (now: " .. C.attack .. ")" },
  { "cryon status",         "Where it is, confessions this session" },
}

function C.help()
  cecho("\n<cyan>Confession of Cryon Frigidus:\n")
  for _, h in ipairs(C.HELP) do cecho(("  <yellow>%-20s<white>%s\n"):format(h[1], h[2])) end
end

function C.command(c, arg)
  if c == nil or c == "help" then C.help()
  elseif c == "start" then C.start(tonumber(arg or "") or 1)
  elseif c == "stop" then C.stop()
  elseif c == "resume" then
    if C.active then return info("yellow", "Already running") end
    C.start(C.left + 1, math.max(C.step, 1))
  elseif c == "attack" and arg then C.attack = arg; info("white", "Fields are attacked with: " .. arg)
  elseif c == "status" then
    local s = C.ROUTE[C.step]
    info("white", (C.active and "Running" or "Stopped") .. ", step " .. C.step .. "/" .. #C.ROUTE ..
      (s and s.title and (" (" .. s.title .. ")") or "") .. ", " .. C.runs .. " confession(s) this session, attack: " .. C.attack)
  else info("yellow", "Unknown command '" .. tostring(c) .. "'. Type cryon help") end
end
