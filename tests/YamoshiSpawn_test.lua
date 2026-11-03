-- Full-run simulation: a fake MUD built from the room exits in the log.
-- Every move must follow a real exit; NPCs answer like they did in the log.
local DIRS = { n = { 0, 1 }, s = { 0, -1 }, e = { 1, 0 }, w = { -1, 0 } }
local W = {}            -- W[zone][x..","..y] = { name, exits = {dir = true} }
local function room(zone, x, y, name) W[zone] = W[zone] or {}; W[zone][x .. "," .. y] = { name = name, x = x, y = y, exits = {} } end
local function link(zone, x1, y1, x2, y2)
  local a, b = W[zone][x1 .. "," .. y1], W[zone][x2 .. "," .. y2]
  assert(a and b, ("bad link %s %d,%d-%d,%d"):format(zone, x1, y1, x2, y2))
  local dx, dy = x2 - x1, y2 - y1
  for d, v in pairs(DIRS) do
    if v[1] == dx and v[2] == dy then a.exits[d] = true end
    if v[1] == -dx and v[2] == -dy then b.exits[d] = true end
  end
end
local function line(zone, pts) for i = 1, #pts - 1 do link(zone, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) end end

-- Temple (Atrium at 0,0)
room("t", 0, 0, "The Echoing Atrium")
for _, p in ipairs({ { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do room("t", p[1], p[2], "Temple of the Ancients"); link("t", 0, 0, p[1], p[2]) end
room("t", -2, 0, "Hallway W1"); room("t", -3, 0, "Hallway W2"); line("t", { { -1, 0 }, { -2, 0 }, { -3, 0 } })
room("t", 0, 2, "Hallway N1"); room("t", 0, 3, "Hallway N2"); line("t", { { 0, 1 }, { 0, 2 }, { 0, 3 } })
room("t", 2, 0, "Hallway E1"); room("t", 3, 0, "Hallway E2"); line("t", { { 1, 0 }, { 2, 0 }, { 3, 0 } })
-- the vortex rooms: "enter vortex" goes through in either direction
local PORTALS = { ["t:-3,0:enter vortex"] = { "mem", 0, -2 }, ["t:0,3:enter vortex"] = { "per", 0, 2 }, ["t:3,0:enter vortex"] = { "pow", 0, 0 },
                  ["mem:0,-2:enter vortex"] = { "t", -3, 0 }, ["per:0,2:enter vortex"] = { "t", 0, 3 }, ["pow:0,0:enter vortex"] = { "t", 3, 0 } }

-- Memory: arrival 0,-2 -> 0,-1 -> crossing 0,0 -> Hall 0,1 -> Kaizor 0,2; square loop x=-2..2, y=0..4
room("mem", 0, -2, "Forgotten Chamber"); room("mem", 0, -1, "Forgotten Chamber"); room("mem", 0, 0, "Forgotten Crossing")
room("mem", 0, 1, "Hall of Memories"); room("mem", 0, 2, "Memories of the First Saiyans")
line("mem", { { 0, -2 }, { 0, -1 }, { 0, 0 }, { 0, 1 }, { 0, 2 } })
local TORCH = { ["-2,0"] = "Pride", ["-2,4"] = "Power", ["2,4"] = "Purpose", ["2,0"] = "Will" }
for x = -2, 2 do for _, y in ipairs({ 0, 4 }) do if not W.mem[x .. "," .. y] then room("mem", x, y, TORCH[x .. "," .. y] and "Chamber of Memories" or "Path of the First Saiyans") end end end
for _, x in ipairs({ -2, 2 }) do for y = 1, 3 do room("mem", x, y, "Path of the First Saiyans") end end
for x = -2, 1 do link("mem", x, 0, x + 1, 0); link("mem", x, 4, x + 1, 4) end
for y = 0, 3 do link("mem", -2, y, -2, y + 1); link("mem", 2, y, 2, y + 1) end

-- Perception: Veiled 0,2 -> Twisted 0,1 -> FC 0,0.5 (use 0,0 for FC and 0,-1 for H0 to keep integers)
room("per", 0, 2, "Veiled Corridor"); room("per", 0, 1, "Chamber of Twisted Reflection"); room("per", 0, 0, "False Corridor")
room("per", 0, -1, "Hall of Uncertainty")                                  -- H0
line("per", { { 0, 2 }, { 0, 1 }, { 0, 0 }, { 0, -1 } })
for x = -3, 3 do if x ~= 0 then room("per", x, -1, "Hall of Uncertainty") end end
room("per", -4, -1, "Chamber of Judgment J1"); room("per", 4, -1, "Chamber of Judgment J2")
for x = -4, 3 do link("per", x, -1, x + 1, -1) end
room("per", 0, -2, "False Corridor"); room("per", 0, -3, "Hall of Uncertainty")   -- L0
line("per", { { 0, -1 }, { 0, -2 }, { 0, -3 } })
room("per", -1, -3, "Hall of Uncertainty"); room("per", 1, -3, "Hall of Uncertainty")
room("per", -2, -3, "Chamber of Judgment J4"); room("per", 2, -3, "Chamber of Judgment J3")
line("per", { { -2, -3 }, { -1, -3 }, { 0, -3 }, { 1, -3 }, { 2, -3 } })
room("per", -1, -4, "False Corridor"); room("per", -1, -5, "Hall of Uncertainty M")
line("per", { { -1, -3 }, { -1, -4 }, { -1, -5 } })
room("per", -2, -5, "Hall of Uncertainty"); room("per", -3, -5, "Hall of Uncertainty"); room("per", -4, -5, "Chamber of Judgment J5")
line("per", { { -1, -5 }, { -2, -5 }, { -3, -5 }, { -4, -5 } })
room("per", 1, -4, "False Corridor"); room("per", 1, -5, "Hall of Uncertainty M'")
line("per", { { 1, -3 }, { 1, -4 }, { 1, -5 } })
room("per", 2, -5, "Hall of Uncertainty"); room("per", 3, -5, "Hall of Uncertainty"); room("per", 4, -5, "Chamber of Judgment J6")
line("per", { { 1, -5 }, { 2, -5 }, { 3, -5 }, { 4, -5 } })
room("per", 1, -6, "False Corridor"); room("per", 0, -6, "Hall of Uncertainty B"); room("per", 0, -7, "Hall of Uncertainty B2")
room("per", 0, -8, "Visions of the First Saiyans")
line("per", { { 1, -5 }, { 1, -6 }, { 0, -6 }, { 0, -7 }, { 0, -8 } })
local TRUE_WARRIOR = { J1 = "ski", J2 = "fat", J3 = "fat", J4 = "mus", J5 = "fat", J6 = "fat" }

-- Power: arrival 0,0 -> Guardian -1,0 -> ... -> centre -5,0; junctions -5,3 and -5,-3; Renzakai -10,0
room("pow", 0, 0, "Iron Passage"); room("pow", -1, 0, "Hall of Champions (Guardian)")
for x = -10, -2 do room("pow", x, 0, x == -10 and "Arena of the First Saiyans" or "Hall/Iron") end
for x = -10, -1 do link("pow", x, 0, x + 1, 0) end
for _, y in ipairs({ 1, 2, 3, -1, -2, -3 }) do room("pow", -5, y, "Iron/Hall") end
line("pow", { { -5, -3 }, { -5, -2 }, { -5, -1 }, { -5, 0 }, { -5, 1 }, { -5, 2 }, { -5, 3 } })
local ARENA = { ["-4,3"] = "Knight", ["-6,3"] = "General", ["-4,-3"] = "King", ["-6,-3"] = "Prince" }
for k in pairs(ARENA) do local x, y = k:match("(-?%d+),(-?%d+)"); room("pow", tonumber(x), tonumber(y), "Underground Arena"); link("pow", -5, tonumber(y), tonumber(x), tonumber(y)) end

-- ---------------------------------------------------------------- fake MUD
local zone, pos = "t", { 0, 0 }
local inbox, sent, bad = {}, {}, {}
local temps, timers, id, now = {}, {}, 0, 0
local state = { torch = 1, extinguished = {}, chambers = {}, warriors = 0, dead = {} }
local FLAMES = { "Purpose", "Will", "Power", "Pride" }
local function here() return W[zone][pos[1] .. "," .. pos[2]] end
local function say(l) inbox[#inbox + 1] = l end

local function arrive()
  local r = here()
  say(r.name)
  if zone == "mem" and r.name == "Hall of Memories" and not state.memStarted then
    say("The Guardian of Memories says, 'Four sacred flames burn with the essence of Vegeta's legacy. You must extinguish them in their proper sequence.'")
  elseif zone == "per" and r.name == "Chamber of Twisted Reflection" and not state.perStarted then
    say("The Guardian of Perception says, 'You will have 5 minutes. Seek them wisely.'")
  elseif zone == "pow" and pos[1] == -1 and not state.powStarted then
    say("The Guardian of Might says, 'Greetings, seeker. I am the Guardian of Might.'")
  end
end

local function mud(cmd)
  sent[#sent + 1] = cmd
  local r = here()
  local key = zone .. ":" .. pos[1] .. "," .. pos[2] .. ":" .. cmd
  if PORTALS[key] then
    local p = PORTALS[key]; zone, pos = p[1], { p[2], p[3] }; return arrive()
  end
  if cmd == "enter vortex" then bad[#bad + 1] = "enter vortex outside a vortex room at " .. r.name; return end
  if cmd == "look" then return say(r.name) end
  -- like the real game: until the maze opens, heading south out of the guardian's rooms
  -- shows the room again followed by the refusal, and you don't move
  if zone == "per" and cmd == "s" and (r.name == "Chamber of Twisted Reflection" or (pos[1] == 0 and pos[2] == 0))
     and now < (state.perOpenAt or 0) then
    state.refusals = (state.refusals or 0) + 1
    say(r.name); return say("You must start the trial to proceed.")
  end
  if DIRS[cmd] then
    if not r.exits[cmd] then bad[#bad + 1] = cmd .. " from " .. r.name .. " " .. pos[1] .. "," .. pos[2]; return say("Alas, you cannot go that way...") end
    pos = { pos[1] + DIRS[cmd][1], pos[2] + DIRS[cmd][2] }; return arrive()
  end
  if cmd == "say ready" then
    if zone == "mem" then
      state.memStarted = true
      say("The Guardian of Memories exclaims, 'Very well. Let the trial begin!'")
      say("The Guardian of Memories says, 'The sequence begins with The Flame of " .. FLAMES[1] .. ".'")
      say("The Guardian of Memories asks, 'Do you wish to undertake this trial?'")
      say("The Guardian of Memories says, 'Then comes The Flame of " .. FLAMES[2] .. ".'")
      say("The Guardian of Memories says, 'Followed by The Flame of " .. FLAMES[3] .. ".'")
      say("The Guardian of Memories says, 'And finally, The Flame of " .. FLAMES[4] .. ".'")
      say("The Guardian of Memories says, 'Remember them well, and seek them in the proper order.'")
    elseif zone == "per" then
      state.perStarted = true
      state.perOpenAt = now + (MAZE_DELAY or 7)   -- the maze opens a few seconds after "Very well"
      say("The Guardian of Perception says, 'Very well. Test your perception wisely.'")
    elseif zone == "pow" then
      state.powStarted = true
      say("The Guardian of Might exclaims, 'Four warriors now descend to challenge you. Defeat them all!'")
    end
  elseif cmd == "extinguish" then
    local t = TORCH[pos[1] .. "," .. pos[2]]
    assert(zone == "mem" and t == FLAMES[state.torch], "extinguished wrong torch at " .. r.name .. " " .. tostring(t))
    state.torch = state.torch + 1
    say("The torch extinguishes with a burst of azure light!")
    if state.torch > 4 then say("All torches have been extinguished! Your memory is proven strong.") end
  elseif cmd:match("^sense ") or cmd:match("^touch ") then
    local j = r.name:match("(J%d)"); assert(j, cmd .. " outside a chamber: " .. r.name)
    local who = cmd:match(" (%a+)$")
    if cmd:match("^sense") then
      -- the game words an echo two ways: alternate them so both are handled
      state.echoes = (state.echoes or 0) + (TRUE_WARRIOR[j] == who and 0 or 1)
      say(TRUE_WARRIOR[j] == who and "The ki signature is stable and bright. No flicker. No hesitation."
          or state.echoes % 2 == 1 and "Something feels wrong. The energy seems... copied, fragmented."
          or "Cold and lifeless. An echo of a warrior, not the real thing.")
    else
      assert(TRUE_WARRIOR[j] == who, "touched a false warrior in " .. j)
      assert(not state.chambers[j], "solved " .. j .. " twice")
      state.chambers[j] = true
      say("They acknowledge your touch! The warrior's ki confirms" .. "-you have found truth!")
    end
  elseif cmd:match("^ss ") then
    local target = cmd:sub(4)
    local boss
    if zone == "mem" and r.name == "Memories of the First Saiyans" and target == "kaizor" then boss = "Warlord Kaizor"
    elseif zone == "per" and r.name == "Visions of the First Saiyans" and target == "varkuun" then boss = "Ruthless Varkuun"
    elseif zone == "pow" and pos[1] == -10 and target == "renzakai" then boss = "Legendary Renzakai"
    elseif zone == "pow" and ARENA[pos[1] .. "," .. pos[2]] and target == "evil" then
      local name = ARENA[pos[1] .. "," .. pos[2]]
      assert(not state.dead[name], "attacked dead " .. name)
      state.dead[name] = true; state.warriors = state.warriors + 1
      say(({ "One warrior falls!", "Two warriors fall!", "Three warriors fall!", "All warriors defeated! The trial is complete!" })[state.warriors])
      return say("Evil Shadow " .. name .. " is dead!  R.I.P.")
    end
    assert(boss, "attack '" .. cmd .. "' with no target at " .. r.name)
    assert(not state.dead[boss]); state.dead[boss] = true
    say(boss .. " is dead!  R.I.P.")
  elseif cmd == "say ritual" then
    assert(zone == "t" and pos[1] == 0 and pos[2] == 0, "ritual away from the altar")
    assert(state.dead["Warlord Kaizor"] and state.dead["Ruthless Varkuun"] and state.dead["Legendary Renzakai"])
    say("The relics resonate with divine power, summoning a legendary presence!")
  end
end

-- ---------------------------------------------------------------- Mudlet stand-ins
function send(c) mud(c) end
function cecho(s) LOG = (LOG or "") .. s end
function tempTrigger(t, f, n) id = id + 1; temps[id] = { t = t, f = f, n = n }; return id end
local RE = {
  [ [[^(Chamber of Twisted Reflection|False Corridor|Hall of Uncertainty)$]] ] = function(l)
    for _, n in ipairs({ "Chamber of Twisted Reflection", "False Corridor", "Hall of Uncertainty" }) do
      if l == n then matches = { l, l }; return true end
    end
  end,
  [ [[^(This presence is solid, certain|The ki signature is stable and bright)]] ] = function(l) return l:find("^This presence is solid, certain") or l:find("^The ki signature is stable and bright") end,
  [ [[^(One warrior falls|Two warriors fall|Three warriors fall|All warriors defeated)!]] ] = function(l)
    return l:find("^One warrior falls!") or l:find("^Two warriors fall!") or l:find("^Three warriors fall!") or l:find("^All warriors defeated!") end,
}
function tempRegexTrigger(p, f, n) id = id + 1; temps[id] = { re = assert(RE[p], p), f = f, n = n }; return id end
function killTrigger(i) if i then temps[i] = nil end end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end

dofile("packages/YamoshiSpawn/src/YamoshiSpawn.lua")
local PERM = {   -- the package's permanent triggers (same patterns as build.py)
  { "You must extinguish them in their proper sequence.", function() ys.guardianReady("memory") end },
  { "Remember them well, and seek them in the proper order.", function() ys.memoryGo() end },
  { "You will have 5 minutes. Seek them wisely.", function() ys.guardianReady("perception") end },
  { "Very well. Test your perception wisely.", function() ys.perceptionGo() end },
  { "Greetings, seeker. I am the Guardian of Might.", function() ys.guardianReady("power") end },
  { "Four warriors now descend to challenge you. Defeat them all!", function() ys.powerGo() end },
  { "The relics resonate with divine power, summoning a legendary presence!", function() ys.summoned() end },
}
local function pump()
  local guard = 0
  while #inbox > 0 do
    guard = guard + 1; assert(guard < 5000, "runaway")
    local l = table.remove(inbox, 1)
    local flame = l:match("^The Guardian of Memories says, '.-The Flame of (%a+)%.'")
    if flame and (l:find("sequence begins with") or l:find("Then comes") or l:find("Followed by") or l:find("And finally,")) then ys.flameNamed(flame) end
    for _, p in ipairs(PERM) do if l:find(p[1], 1, true) then p[2]() end end
    local ids = {}; for i in pairs(temps) do ids[#ids + 1] = i end; table.sort(ids)
    for _, i in ipairs(ids) do
      local t = temps[i]
      if t and ((t.t and l:find(t.t, 1, true)) or (t.re and t.re(l))) then
        if t.n then t.n = t.n - 1; if t.n <= 0 then temps[i] = nil end end
        t.f()
      end
    end
  end
end

ys.command("start")
pump()
for _ = 1, 400 do
  now = now + 0.5
  local due = {}
  for i, t in pairs(timers) do if t.at <= now then due[#due + 1] = i end end
  table.sort(due)
  for _, i in ipairs(due) do local t = timers[i]; if t then timers[i] = nil; t.f(); pump() end end
end

print(table.concat(sent, " "))
assert(#bad == 0, "invalid moves: " .. table.concat(bad, "; "))
assert(state.torch == 5, "torches done: " .. state.torch - 1)
for j in pairs(TRUE_WARRIOR) do assert(state.chambers[j], j .. " not solved") end
assert(state.warriors == 4)
assert(ys.stage == "done" and not ys.active, "ended at stage " .. ys.stage)
assert(not (LOG or ""):find("Timed out"), "a wait timed out")
print("\nFULL YAMOSHI RUN PASSED: " .. #sent .. " commands, 0 invalid moves, " .. (state.refusals or 0) .. " maze refusals")

-- ---------------------------------------------------------------- quiz and yamoportal
local out = {}
function send(c) out[#out + 1] = c end
local function quizLine(l)
  local q = l:match("^Tetsu[ks]ai asks, '(.+)") or l:match("^Tetsu[ks]ai says, '(.+)")
  if q then return ys.quiz(q) end
end
local QUIZ = {
  { "Tetsukai says, 'Yamoshi and his comrades performed this to unlock Yamoshi's true potential.'", "ritual" },
  { "Tetsusai asks, 'A Elder of this race was moved by Yamoshi's tale and penned the Book of Yamoshi. Which race?'", "namek" },
  { "Tetsukai asks, 'During the Divine Ritual... What was the color of the aura that surrounded us?'", "blue" },
  { "Tetsusai asks, 'While battling the evil Saiyans... What was Yamoshi's ultimate fate?'", "death" },
  { "Tetsukai asks, 'How many saiyans did Yamoshi seek out to perform the divine ritual?'", "5" },
  { "Tetsukai asks, 'The divine ritual unlocked what ability in Yamoshi long after his death?'", "Super Saiyan God" },
  { "Tetsukai asks, 'What quality burned in the hearts of Yamoshi's comrades?'", "Righteousness" },
  { "Tetsusai asks, 'Before his death, Yamoshi fought bravely to defeat which threat?'", "Evil Saiyans" },
  { "Tetsusai asks, 'When he battled the Evil Saiyans, what form did Yamoshi achieve?'", "SSJ" },
  { "Tetsusai says, 'After his death he did this for a millenia seeking out comrades in arms.'", "Wander" },
}
for _, qa in ipairs(QUIZ) do
  out = {}
  assert(quizLine(qa[1]) == qa[2], "quiz: " .. qa[1])
  assert(out[1] == "say " .. qa[2] and #out == 1, "quiz sent: " .. table.concat(out, " | "))
end
out = {}
assert(quizLine("Tetsukai says, 'Welcome, traveller.'") == nil and #out == 0, "unknown line answered")

out = {}; ys.portal(true)
assert(#out == 22, "yamoportal sends " .. #out)
local searches = 0
for _, c in ipairs(out) do if c == "search;;get fragment" then searches = searches + 1 end end
assert(searches == 7 and out[1] == "search;;get fragment" and out[22] == "search;;get fragment")
out = {}; ys.portal(false)
assert(#out == 15, "yamoportal no sends " .. #out)
for _, c in ipairs(out) do assert(c ~= "search;;get fragment") end
assert(table.concat(out, ",") == "press switch,press switch,enter portal,press switch,enter portal,press switch,enter portal,press switch,press switch,enter portal,press switch,enter portal,press switch,press switch,enter portal")
print("QUIZ AND YAMOPORTAL PASSED")
