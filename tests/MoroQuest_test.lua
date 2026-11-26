-- moro: the Moro questline. Run from the repo root: lua tests/MoroQuest_test.lua
local now, id, timers, temps, inbox, sent = 0, 0, {}, {}, {}, {}
local respond
function send(c) sent[#sent + 1] = c; if respond then respond(c) end end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
function tempTrigger(t, f) id = id + 1; temps[id] = { t = t, f = f }; return id end
local RE = {
  [ [[^\s*(\d+)\. (.+), go \w+]] ] = function(l) local n, a = l:match("^%s*(%d+)%. (.+), go %a+"); if n then return { l, n, a } end end,
  [ [[^.*$]] ] = function(l) return { l } end,
}
function tempRegexTrigger(p, f) id = id + 1; temps[id] = { re = assert(RE[p], p), f = f }; return id end
function killTrigger(i) if i then temps[i] = nil end end
local function say(l) inbox[#inbox + 1] = l end
local function pump()
  while #inbox > 0 do
    local l = table.remove(inbox, 1)
    line = l
    moro.line(l)
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
dofile("packages/MoroQuest/src/MoroQuest.lua")

-- 1. the manifest --------------------------------------------------------------------
ok(moro.decode("Ydqwd", "A", "D") == "Vanta", "A reads as D: Ydqwd is Vanta")
say("Merus says, 'Here is the prisoner manifest and a Patrol rebreather. The breach scrambled the five ")
run(1)
ok(sent[1] == "look prisonmanifest", "Merus hands it over: looks at it")
sent, LOG = {}, ""
say("Prisoner manifest. The broken seal prints the Patrol key: A reads as D. Priority names: Ydqwd, ")
say("Eudnnd, Ulphedfn, Whnwhn, Vdjdqer. 0 of 5 deciphered.")
run(1)
ok(table.concat(moro.names, ",") == "Vanta,Brakka,Rimeback,Tektek,Saganbo", "wrapped manifest: " .. table.concat(moro.names, ","))
ok(LOG:find("Vanta, Brakka, Rimeback, Tektek, Saganbo", 1, true) and #sent == 0, "shown, nothing sent")
moro.command("decipher")
ok(table.concat(sent, "|") == "decipher Vanta|decipher Brakka|decipher Rimeback|decipher Tektek|decipher Saganbo", "moro decipher")
ok(moro.decode("Tyllyx", "B", "Z") == "Vannaz", "another key: B reads as Z")
ok(table.concat(moro.parseLeft("... Still to post: Vegeta, Namek, Iceria and Konats."), ",") == "Vegeta,Namek,Iceria,Konats"
   and #moro.parseLeft("Still to post: none.") == 0, "reads what's still to post")

-- 2. the bulletins, in a model of the five legs ----------------------------------------
local PIN = {
  Earth  = "You pin a bulletin to the Earth spaceport's arrivals board. A courier stops, reads it twice and hurries off.",
  Vegeta = "You pin a bulletin beside the Zenkonia departures board. A Saiyan reads it and laughs.",
  Namek  = "You pin a bulletin to the Namek spaceport's notice stone. An elder nods slowly.",
  Iceria = "You pin a bulletin to the frosted board of the Iceria spaceport. It freezes to the board at once.",
  Konats = "You pin a bulletin on the Konats spaceport's gate. A swordsman reads it and loosens his blade.",
}
local ORDER = { "Earth", "Vegeta", "Namek", "Iceria", "Konats" }
local left = { Earth = true, Vegeta = true, Namek = true, Iceria = true, Konats = true }
local walked, planet, area, rivalDone, surveyNo = {}, nil, nil, false, {}
local VORTEX = { ["s,s"] = "Earth", ["s,e,e"] = "Vegeta", ["s,w,w"] = "Namek", ["n,w,w"] = "Iceria", ["n,e,e"] = "Konats" }
local SURVEY = { Space = { "Galactic Federation HeadQuarters", "Planet Earth", "Installation 04", "Planet Vegeta", "Lucky M(*)nkey Casino",
                   "Planet Iceria", "Golia Clan Starship", "Planet Konats", "Planet Namek", "Galactic Patrol Station",
                   "Brigade Anchorage", "Prison Planet", "Withered Planet" },
                 Namek = { "Kami's Lookout", "Guru's Compound" }, Iceria = { "Clifftop Village", "Crystal Grotto", "Iron Maiden Heights", "Frostblight Cavern", "City of Zero Nexus" } }
local path = {}
local function leftText()
  local l = {}
  for _, p in ipairs(ORDER) do if left[p] then l[#l + 1] = p end end
  if #l == 0 then return "none" end
  if #l == 1 then return l[1] end
  return table.concat(l, ", ", 1, #l - 1) .. " and " .. l[#l]
end
respond = function(c)
  if c == "recall" then path = {}; planet = nil
  elseif c == "crecall" then path = {}; planet = nil; say("Galactic Federation HeadQuarters")
  elseif c == "leave" then planet = "Space"
  elseif c == "press button" then say("A Grand Atrium")
  elseif c == "enter vortex" then planet = VORTEX[table.concat(path, ",")]; assert(planet, "no vortex at " .. table.concat(path, ",")); say("You step through the portal.")
  elseif c == "n" or c == "s" or c == "e" or c == "w" then
    path[#path + 1] = c
    if planet == "Station" and table.concat(path, ",") == "n,n,w" then
      say("Communications Deck")
      say("The projector pad flickers and a small figure in a Patrol uniform appears, recorded: Jaco of the Galactic Patrol, Earth station.")
      say("The recording ends with coordinates: the Prison Planet, landmark 12 on the Space Map survey.")
    end
  elseif c == "survey" then
    say("Nearby Locations:")
    for i, a in ipairs(SURVEY[planet]) do
      say(i == 1 and planet == "Space" and (" 1. " .. a .. " (you are here)") or string.format("%2d. %s, go East", i, a))
    end
    say("Use the 'survey <area number> fly' to navigate a specific area.")
  elseif c:match("^survey (%d+) fly$") then
    local n = tonumber(c:match("^survey (%d+) fly$")); area = SURVEY[planet][n]
    say("- " .. area .. ", go North.")
    say(planet == "Space" and ("You have arrived at " .. area .. ".") or ("You land on the ground in front of " .. area .. "."))
  elseif c == "enter" and planet == "Space" then planet = "Station"; path = {}; say("Patrol Station Hangar")
  elseif c == "enter" then say(area == "Guru's Compound" and "Guru's Compound - Entrance" or "Zero Nexus - City Gates")
  elseif c:match("^pursue ") then
    say("You begin tracking someone's ki...")
    if planet == "Namek" and not rivalDone then
      say("Transform the Changeling flies out of nowhere and attacks you!")
      say("Transform the Changeling exclaims, 'You won't stand a chance, Vorricer!'")
    else say("You have successfully tracked down " .. c:sub(8) .. "!") end
  elseif c == "de transform" then rivalDone = true; say("Transform the Changeling is dead!  R.I.P.")
  elseif c == "post bulletin" then
    walked[#walked + 1] = planet .. ":" .. table.concat(path, "")
    left[planet] = nil
    if planet == "Iceria" then say(PIN[planet]); say("Still to post: " .. leftText() .. ".")   -- wrapped
    else say(PIN[planet] .. " Still to post: " .. leftText() .. ".") end
    if leftText() == "none" then say("That is all five. Your Patrol band chirps: a recorded transmission waits for you on the Station's comms deck.") end
  end
end
sent, LOG = {}, ""
moro.command("bulletins")
run(60)
ok(next(left) == nil, "all five posted")
ok(table.concat(walked, " ") == "Earth:ssws Vegeta:see Namek:sww Iceria:nwwnnnw Konats:nees", "each walked its own way: " .. table.concat(walked, " "))
local s = table.concat(sent, "|")
ok(s:find("survey 2 fly", 1, true) and s:find("survey 5 fly", 1, true), "survey numbers read from the list")
ok(s:find("de transform|pursue guide", 1, true), "rival: fought, then the pursue again")
ok(LOG:find("All five bulletins posted", 1, true), "says what's next")
ok(s:find("crecall|leave|survey|survey 10 fly|enter|n|n|w", 1, true), "then on to the comms deck: " .. s:sub(-50))
ok(moro.landmark == 12 and LOG:find("Prison Planet, landmark 12", 1, true), "transmission played: Prison Planet, landmark 12")
ok(next(temps) == nil and next(timers) == nil, "nothing left running")
-- only what's still to post, and a single planet
left = { Namek = true, Konats = true }; walked, sent = {}, {}
moro.left = { "Namek", "Konats" }
moro.command("bulletins")
run(60)
ok(table.concat(walked, " ") == "Namek:sww Konats:nees", "picks up from 'Still to post': " .. table.concat(walked, " "))
left = { Vegeta = true, Iceria = true }; walked = {}
moro.command("post", "vegeta")
run(30)
ok(table.concat(walked, " ") == "Vegeta:see" and left.Iceria, "moro post vegeta: just that one")
-- a step that never answers: stops with a message
respond = function() end
LOG = ""; moro.command("bulletins", "earth"); run(60)
ok(LOG:find("Timed out", 1, true) and next(temps) == nil and next(timers) == nil, "a stuck step times out and cleans up")
moro.command("comms"); moro.command("stop")
ok(next(temps) == nil and next(timers) == nil, "moro stop cleans up the comms run")
moro.command("bulletins", "earth"); moro.command("stop")
ok(next(temps) == nil and next(timers) == nil, "moro stop cleans up")
print("\nmoro: ALL PASSED")
