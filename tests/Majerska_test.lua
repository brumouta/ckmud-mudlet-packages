-- maj: Majerska's Cursed Canopy. Run from the repo root: lua tests/Majerska_test.lua
local now, id, timers, temps, inbox, sent = 0, 0, {}, {}, {}, {}
local respond
function send(c) sent[#sent + 1] = c; if respond then respond(c) end end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
function tempTrigger(t, f) id = id + 1; temps[id] = { t = t, f = f }; return id end
local RE = {
  [ [[^\s*(\d+)\. (.+), go \w+]] ] = function(l) local n, a = l:match("^%s*(%d+)%. (.+), go %a+"); if n then return { l, n, a } end end,
  [ [[^\[B\]\[]] ] = function(l) if l:find("^%[B%]%[") then return { l } end end,
  [ [[^[A-Z][\w' ]* who\?$]] ] = function(l) if l:match("^%u[%w' ]* who%?$") then return { l } end end,
}
function tempRegexTrigger(p, f) id = id + 1; temps[id] = { re = assert(RE[p], p), f = f }; return id end
function killTrigger(i) if i then temps[i] = nil end end
local function say(l) inbox[#inbox + 1] = l end
local function pump()
  while #inbox > 0 do
    local l = table.remove(inbox, 1)
    line = l
    maj.line(l)
    local ids = {}; for i in pairs(temps) do ids[#ids + 1] = i end; table.sort(ids)
    for _, i in ipairs(ids) do
      local t = temps[i]
      if t then
        if t.t and l:find(t.t, 1, true) then matches = { t.t }; t.f()
        elseif t.re then local m = t.re(l); if m then matches = m; t.f() end end
      end
    end
  end
end
local function run(secs)
  pump()
  for _ = 1, secs * 2 do
    now = now + 0.5
    local due = {}
    for i, t in pairs(timers) do if t.at <= now then due[#due + 1] = i end end
    table.sort(due)
    for _, i in ipairs(due) do local t = timers[i]; if t then timers[i] = nil; t.f(); pump() end end
  end
end
local function ok(c, what) assert(c, what); print("OK  " .. what) end
dofile("packages/Majerska/src/Majerska.lua")

local b = maj.parseBoss("[B][1,450,000,000,001]Kragul          - Majerska's Cursed Canopy: Cracking Branches and Boughs")
ok(b and b.name == "Kragul" and b.pl == 1450000000001 and b.room == "Cracking Branches and Boughs", "reads a padded boss line")

-- a model of the trip and the Canopy (the real `where` list)
local WHERE = [[
[B][1,021,013,972,463]Malakar the Damned - Majerska's Cursed Canopy: Lower Canopy
[B][1,350,000,000,001]Vorzeth the Banelord - Majerska's Cursed Canopy: Lower Canopy
[B][1,400,000,000,001]Zarvok the Planet Eater - Majerska's Cursed Canopy: Lower Canopy
[B][1,450,000,000,001]Kragul          - Majerska's Cursed Canopy: Cracking Branches and Boughs
[B][1,500,000,000,001]Xenthros Doomfist - Majerska's Cursed Canopy: Cracking Branches and Boughs
[B][1,600,000,000,001]Ragathar Voidbeam - Majerska's Cursed Canopy: Cracking Branches and Boughs
[B][1,650,000,000,001]Nyzakar the Spirit Leech - Majerska's Cursed Canopy: Dark and Gloomy Branches
[B][1,700,000,000,001]Draegon Maliceborn - Majerska's Cursed Canopy: Dark and Gloomy Branches
[B][1,750,000,000,001]Zel-zan Darkheart - Majerska's Cursed Canopy: Dark and Gloomy Branches
[B][1,800,000,000,001]Multar the Dreadful - Majerska's Cursed Canopy: Continously Shifting Offshoots
[B][1,850,000,000,001]Drazhion the Shade - Majerska's Cursed Canopy: Continously Shifting Offshoots
[B][1,900,000,000,001]Valbun          - Majerska's Cursed Canopy: High Canopy
[B][1,950,000,000,001]Xaldrak the Void Sorcerer - Majerska's Cursed Canopy: High Canopy
[B][1,550,000,000,001]Belzuron        - Majerska's Cursed Canopy: Cracking Branches and Boughs]]
local alive, byKey, path, killed, inside = {}, {}, {}, {}, false
for l in WHERE:gmatch("[^\n]+") do
  local x = maj.parseBoss(l); alive[x.name] = l; byKey[x.name:match("^(%S+)"):lower()] = x.name
end
local SURVEY = { "Frozen Valley", "Z Fighters HeadQuarters", "The Sacred Land", "Time Patrol HeadQuarters", "Majerska's Cursed Canopy", "Babidi's Spaceship" }
local rivalDone, here, ghost = false, nil, true
respond = function(c)
  if c == "recall" then path = {}
  elseif c == "s" then path[#path + 1] = c
  elseif c == "enter vortex" then assert(table.concat(path) == "ss"); say("You step through the portal."); say("a grassy field")
  elseif c == "survey" then
    say("Nearby Locations:")
    for i, a in ipairs(SURVEY) do say(string.format("%2d. %s, go North", i, a)) end
  elseif c == "survey 5 fly" then say("- Majerska's Cursed Canopy, go North."); say("You land on the ground in front of Majerska's Cursed Canopy.")
  elseif c == "enter" then inside = true
  elseif c == "where" then
    assert(inside, "where outside")
    say("Majerska's Cursed Canopy:")
    for l in WHERE:gmatch("[^\n]+") do if alive[maj.parseBoss(l).name] then say(l) end end
    say("o------------------------------------------------------------o")
  elseif c:match("^pursue ") then
    local who = byKey[c:sub(8)]
    assert(who and alive[who], "pursue " .. c)
    if who == "Kragul" and not rivalDone then say("Transform the Changeling flies out of nowhere and attacks you!"); return end
    here = who
    say("You have successfully tracked down " .. who .. "!")
  elseif c == "de transform" then rivalDone = true; say("Transform the Changeling is dead!  R.I.P.")
  elseif c:match("^de ") then
    local who = byKey[c:sub(4)]
    assert(who == here, "attacking " .. tostring(who) .. " away from it")
    if who == "Valbun" and ghost then ghost = false; here = nil; say("Death Beam who?"); return end
    killed[#killed + 1] = who; alive[who] = nil
    say(who .. " is dead!  R.I.P.")
  end
end
maj.command("go")
run(300)
ok(#killed == 14 and next(alive) == nil, "all 14 dead")
ok(killed[1] == "Malakar the Damned" and killed[5] == "Xenthros Doomfist" and killed[6] == "Belzuron" and killed[14] == "Xaldrak the Void Sorcerer",
   "weakest first: " .. table.concat(killed, ", "))
local s = table.concat(sent, "|")
ok(s:find("recall|press button|s|s|enter vortex|survey|survey 5 fly|enter|where|pursue malakar|de malakar", 1, true), "travels, enters, reads where")
ok(s:find("pursue kragul|de transform|pursue kragul|de kragul", 1, true), "rival: fought, then the boss pursued again")
ok(s:find("de valbun|pursue valbun|de valbun", 1, true), "boss moved away (who?): pursued again")
ok(s:find("pursue zel-zan", 1, true), "hyphenated first name")
ok(LOG:find("clear (14 killed)", 1, true), "says it's clear")
ok(next(temps) == nil and next(timers) == nil, "nothing left running")

-- a boss that can't be found is skipped, not looped on
alive = { ["Valbun"] = WHERE:match("[^\n]*Valbun[^\n]*") }
respond = function(c)
  if c == "where" then say(alive.Valbun)
  elseif c:match("^pursue ") then say("You sense no ki.") end
end
LOG, sent = "", {}
maj.command("kill")
run(120)
ok(LOG:find("skipped: Valbun", 1, true) and next(temps) == nil and next(timers) == nil, "unreachable boss skipped, then done")
maj.command("kill"); maj.command("stop")
ok(next(temps) == nil and next(timers) == nil, "maj stop cleans up")
print("\nmaj: ALL PASSED")
