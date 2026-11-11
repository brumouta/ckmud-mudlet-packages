-- cryon: a whole confession run in a fake Iceria. The lower lab is a grid built from the exits in
-- the log, so a wrong turn walks into a wall. Run from the repo root: lua tests/CryonFarm_test.lua
local now, timers, nextId, sent = 0, {}, 0, {}
function getEpoch() return now end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) nextId = nextId + 1; timers[nextId] = { at = now + d, f = f }; return nextId end
function killTimer(i) timers[i] = nil end
local respond
function send(c) sent[#sent + 1] = c; if respond then respond(c) end end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end
local function wait(secs)
  local target = now + secs
  while true do
    local best, id
    for i, t in pairs(timers) do if t.at <= target and (not best or t.at < best.at) then best, id = t, i end end
    if not best then break end
    timers[id] = nil; now = best.at; best.f()
  end
  now = target
end

dofile("packages/CryonFarm/src/CryonFarm.lua")
local C = cryon
local function out(lines, delay) tempTimer(delay or 0.1, function() for _, l in ipairs(lines) do C.line(l) end end) end

-- Upstairs: the walk as it was in the log, one room after another
local UP = {
  { "s", "Commerce Way" }, { "e", "Commerce Way" }, { "e", "Commerce Way" }, { "s", "Commerce Way" }, { "s", "Commerce Way" },
  { "e", "Commerce Way" }, { "e", "Commerce Way" }, { "e", "Frost Plaza" }, { "e", "Frost Plaza" }, { "n", "snow covered path" },
  { "n", "Zero Nexus Research Facility" }, { "n", "Research Facility Atrium" }, { "n", "Research Facility Atrium" },
  { "n", "Research Facility Atrium" }, { "n", "Research Facility Atrium" },
  { "e", "Hidden Hallway" }, { "e", "Hidden Hallway" }, { "e", "Hidden Hallway" }, { "e", "Hidden Laboratory" },
  { "s", "Hidden Laboratory" }, { "s", "Hidden Laboratory" }, { "e", "Hidden Laboratory" }, { "e", "Hidden Laboratory" },
  { "e", "Hidden Laboratory" }, { "n", "Hidden Laboratory" }, { "n", "Hidden Laboratory" }, { "e", "Incubation Chamber" },
  { "e", "Hidden Laboratory" }, { "e", "Hidden Laboratory" }, { "e", "Hidden Laboratory" }, { "e", "Hidden Laboratory" },
}

-- Downstairs: Control Room at 0,0, a plus of hallways, a 3x3 chamber in each corner
local G = {}
local function cell(x, y, title) G[x .. "," .. y] = title end
for i = 1, 4 do cell(0, i, "Hallway"); cell(0, -i, "Hallway"); cell(i, 0, "Hallway"); cell(-i, 0, "Hallway") end
cell(0, 3, "Hallway Intersection"); cell(0, -3, "Hallway Intersection"); cell(3, 0, "Hallway Intersection"); cell(-3, 0, "Hallway Intersection")
local BLOCK = { { 1, 1, "Pyrokinetic Mutation Chamber" }, { 1, -1, "Electromagnetic Mutation Chamber" },
                { -1, -1, "Cryogenic Mutation Chamber" }, { -1, 1, "Genetic Amplification Chamber" } }
for _, b in ipairs(BLOCK) do
  for dx = 2, 4 do for dy = 2, 4 do cell(b[1] * dx, b[2] * dy, b[3]) end end
  cell(b[1] * 1, b[2] * 3, "Entrance to the " .. b[3]); cell(b[1] * 3, b[2] * 1, "Entrance to the " .. b[3])
end
-- the hallway past each intersection stops at the chambers' entrances
G["4,0"], G["-4,0"], G["0,-4"] = nil, nil, nil
G["0,0"] = "Control Room"
local function exits(x, y)
  local t = G[x .. "," .. y]
  local e = {}
  for d, v in pairs({ n = { 0, 1 }, s = { 0, -1 }, e = { 1, 0 }, w = { -1, 0 } }) do
    local t2 = G[(x + v[1]) .. "," .. (y + v[2])]
    if t2 then
      local inChamber = not t:find("Hall") and not t:find("Entrance") and t ~= "Control Room"
      local inChamber2 = not t2:find("Hall") and not t2:find("Entrance") and t2 ~= "Control Room"
      -- chamber cells only join their own chamber or its entrance; hallways only join hallways and entrances
      local okLink = (inChamber and inChamber2 and t == t2) or (inChamber and t2 == "Entrance to the " .. t)
        or (inChamber2 and t == "Entrance to the " .. t2) or (not inChamber and not inChamber2
        and not (t:find("Entrance") and t2:find("Entrance")))
      if okLink then e[d] = { x + v[1], y + v[2] } end
    end
  end
  return e
end
-- The log's exits, checked against the grid
local function dirs(x, y) local o = {} for d in pairs(exits(x, y)) do o[#o + 1] = d end table.sort(o) return table.concat(o) end
ok(dirs(0, 3) == "ensw", "north Hallway Intersection: N E S W, as in the log")
ok(dirs(-3, 0) == "ens", "west Hallway Intersection: N E S, as in the log")
ok(dirs(4, -2) == "sw" and dirs(2, -3) == "ensw" and dirs(3, -2) == "ensw", "Electromagnetic chamber rooms, as in the log")

local W = { up = 0, x = nil, y = nil, fields = { ["3,-2"] = true, ["4,-3"] = true, ["3,-4"] = true, ["2,-3"] = true },
            walls = 0, samples = 0, confessions = 0 }
local CENTRE = { ["3,3"] = "pyro", ["3,-3"] = "electro", ["-3,-3"] = "cryo", ["-3,3"] = "genetic" }
local function show(title, extra)
  local lines = { title, "Status:  Normal", "Gravity: Normal    Regen: Normal", "Obvious exits:" }
  for _, l in ipairs(extra or {}) do lines[#lines + 1] = l end
  out(lines)
end
local function showCell()
  local key = W.x .. "," .. W.y
  local extra = {}
  if W.fields[key] then extra[#extra + 1] = "An Electromagnetic Field is blocking the path to a Kidnapped Icerian Citizen." end
  show(G[key], extra)
  if CENTRE[key] == "genetic" then
    out({ "The Kidnapped Icerian Citizen begins to groan uncontrollably." }, 2)
    out({ "Kidnapped Icerian Citizen says, 'Where...am I?'" }, 4)
    out({ "Kidnapped Icerian Citizen says, 'What...am I..doing here?'" }, 6)
    out({ "Kidnapped Icerian Citizen says, 'How..did...I..get here?'" }, 8)
  end
end

respond = function(c)
  if c == "it innkeeper" then W.up, W.x = 0, nil; return show("Blizzards Edge Inn") end
  if W.x == nil then
    local nxt = UP[W.up + 1]
    if not nxt or nxt[1] ~= c then W.walls = W.walls + 1; return out({ "Alas, you cannot go that way..." }) end
    W.up = W.up + 1
    show(nxt[2])
    if W.up == 15 then
      out({ "You swipe the Hidden Laboratory Access Card through the reader, and a faint click echoes through the Atrium." }, 0.5)
      tempTimer(1, function() show("Hidden Hallway") end)
    elseif W.up == 27 then
      out({ "A chill runs down your spine as you step forward." }, 0.5)
      tempTimer(1, function() C.line("You slip into a trapdoor and the air gets thicker."); show("Hidden Laboratory") end)
    end
    if W.up == 31 then W.x, W.y = "lab", 0 end
    return
  end
  if W.x == "lab" and c == "d" then W.x, W.y = 0, 0; return showCell() end
  local v = ({ n = { 0, 1 }, s = { 0, -1 }, e = { 1, 0 }, w = { -1, 0 } })[c]
  if v then
    local to = exits(W.x, W.y)[c]
    if not to then W.walls = W.walls + 1; return out({ "Alas, you cannot go that way..." }) end
    if to[1] .. "," .. to[2] == "3,-3" and next(W.fields) then W.walls = W.walls + 1; return out({ "The Electromagnetic Field stops you." }) end
    W.x, W.y = to[1], to[2]
    return showCell()
  end
  local key = W.x and (W.x .. "," .. W.y)
  if c == "fg f" and W.fields[key] then
    W.fields[key] = nil
    out({ "You point your finger towards Electromagnetic Field and unleash the Galick Gun.", "An Elite Icerian Mercenary comes charging in!" })
    out({ "The Electromagnetic Field blocking the path to the Kidnapped Icerian Citizen " .. (next(W.fields) and "weakens!" or "shatters!"),
          "Elite Icerian Mercenary is dead!  R.I.P." }, 3)
    return
  end
  if c == "extract" and CENTRE[key] and CENTRE[key] ~= "genetic" then
    W.samples = W.samples + 1
    if CENTRE[key] == "cryo" then
      out({ "Vorrac reaches out and carefully releases the Kidnapped Icerian Citizen from its stasis." })
      out({ "Vorrac points the Needleless Syringe at the Kidnapped Icerian Citizen and collects a sample." }, 4)
    else
      out({ "Vorrac points the Needleless Syringe at the Kidnapped Icerian Citizen and collects a sample." })
    end
    return
  end
  if c == "say kidnapped" and CENTRE[key] == "genetic" then
    out({ "You say, 'kidnapped'", "Kidnapped Icerian Citizen says, 'Kidnapped? I..I..remember...going for a stroll..a stroll by Frost Plaza.'" })
    out({ "Kidnapped Icerian Citizen says, 'Then I...I...'", 'The Kidnapped Icerian Citizen begins to pass out, "SMACK" him awake!' }, 5)
    return
  end
  if c == "smack citizen" and CENTRE[key] == "genetic" then
    W.confessions = W.confessions + 1
    W.samples = W.samples + 1
    out({ "Cryon Frigidus says, 'I have already given you my confession. But here it is again.'",
          "Cryon Frigidus gives you Confession of Cryon Frigidus.",
          "Vorrac points the Needleless Syringe at the Kidnapped Icerian Citizen and collects a sample." })
  end
end

C.start()
for _ = 1, 200 do if not C.active then break end wait(5) end
ok(not C.active, "the run ends")
ok(W.walls == 0, "never walked into a wall or the field (" .. #sent .. " commands)")
ok(W.samples == 4 and W.confessions == 1 and C.runs == 1, "four samples and the confession")
ok(not next(W.fields), "all four Electromagnetic Fields killed before the centre")
local said = table.concat(sent, ",")
ok(said:find("say kidnapped,smack citizen", 1, true), "say kidnapped, then smack citizen")
ok(LOG:find("Confession #1. Done", 1, true), "reports it")

-- One run per respawn: BossTimer knows when that is
local function reset() W.up, W.x, W.walls, W.samples, W.confessions = 0, nil, 0, 0, 0
  W.fields = { ["3,-2"] = true, ["4,-3"] = true, ["3,-4"] = true, ["2,-3"] = true }; sent = {} end
ok(LOG:find("next run after the respawn (uptime)", 1, true), "without BossTimer: says to wait for the respawn")
BossTimer = { remaining = function() return BossTimer.at - now end, at = now + 600 }
reset(); LOG = ""
C.start(true)
for _ = 1, 200 do if not C.active then break end wait(5) end
ok(W.confessions == 1 and LOG:find("next run after the respawn, in", 1, true), "with BossTimer: says how long until the next run")
sent = {}; LOG = ""
C.command("start")
ok(#sent == 0 and LOG:find("Already farmed this respawn", 1, true), "cryon start again before the respawn: refuses")
wait(600)
reset(); LOG = ""
C.command("start")
for _ = 1, 200 do if not C.active then break end wait(5) end
ok(W.confessions == 1, "after the respawn it runs again")
BossTimer = nil

-- A wrong attack stops at the first field, and resume carries on
reset(); LOG = ""
C.command("attack", "kick f")
C.start(true)
for _ = 1, 200 do if not C.active then break end wait(5) end
ok(not C.active and LOG:find("didn't go down", 1, true) and W.x == 3 and W.y == -2, "wrong attack: stops in the first field room")
C.command("attack", "fg f")
C.command("resume")
for _ = 1, 200 do if not C.active then break end wait(5) end
ok(W.confessions == 1 and W.walls == 0, "cryon resume picks up from there and finishes")

print("cryon: ALL PASSED")
