-- Smoke test: drive fq through the quest with mocked Mudlet functions.
local sent, temps, timers, id, now = {}, {}, {}, 0, 0
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function tempTrigger(t, f, n) id = id + 1; temps[id] = { t = t, f = f, n = n }; return id end
function tempRegexTrigger(p, f, n)
  local map = { ["^o-+o$"] = "^o%-+o$", ["^After searching around you managed to uncover (.+)!$"] = "^After searching around you managed to uncover (.+)!$" }
  id = id + 1; temps[id] = { p = assert(map[p], p), f = f, n = n }; return id
end
function killTrigger(i) if i then temps[i] = nil end end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    local ids = {}; for i in pairs(temps) do ids[#ids + 1] = i end; table.sort(ids)
    for _, i in ipairs(ids) do
      local t = temps[i]
      if t then
        local hit = t.t and l:find(t.t, 1, true) or (t.p and l:match(t.p))
        if hit then
          matches = { l, t.p and l:match(t.p) or nil }
          if t.n then t.n = t.n - 1; if t.n <= 0 then temps[i] = nil end end
          t.f()
        end
      end
    end
  end
end
local function wait(s) now = now + s
  local due = {}
  for i, t in pairs(timers) do if t.at <= now then due[#due + 1] = i end end
  table.sort(due)
  for _, i in ipairs(due) do local t = timers[i]; if t then timers[i] = nil; t.f() end end end
local function expect(w) local g = table.concat(sent, " | "); sent = {}
  assert(g == w, "\n got: " .. g .. "\nwant: " .. w); print("OK  " .. (w == "" and "(nothing)" or w)) end
local SEP = "o------------------------------------------------------------o"
local function locate(kw, item)
  feed("Your scouter scans your inventory for '" .. kw .. "'...\n" .. SEP .. "\n" ..
       (item or "No matching items found in your inventory.") .. "\n" .. SEP)
end
local PW = "say dief | say epikoin | say kinitiras | say exousia"
local OPEN = "With the voice pattern confirmed, the hatch swings open."

dofile("packages/FriezaQuest/src/FriezaQuest.lua")
-- item check: dark matter missing -> not started, nothing fetched
fq.command("start"); expect("locate evermore")
locate("evermore", "an Evermore Fusion Cell"); expect("locate tufftech")
locate("tufftech", "a TuffTech x45 battery"); expect("locate matter")
locate("matter"); expect("locate premium")
locate("premium", "a premium circuit board"); expect("")
assert(not fq.active and LOG:find("Missing: lump of dark matter"))
-- all present -> started
fq.command("start"); locate("evermore", "an Evermore Fusion Cell"); locate("tufftech", "a TuffTech x45 battery")
locate("matter", "a lump of dark matter"); locate("premium", "a premium circuit board")
expect("locate evermore | locate tufftech | locate matter | locate premium")
assert(fq.active and fq.stage == "appule")
-- Appule in the south Airlock
fq.room("Airlock"); fq.exit("South", "Entrance to Frieza's Spaceship")
fq.appuleHere(); expect("ss appule")
fq.appuleDead(); expect("get caps | s")          -- no "e" into the sealed hatch
feed("The seals of the Hatch automatically release."); fq.sealReleased(); expect("e | " .. table.concat(fq.TO_CUI, " | "))
assert(fq.stage == "cuicui")
-- fq go from the Hatch walks to Cui Cui; from elsewhere it says where to go
fq.room("Hatch"); fq.command("go"); expect(table.concat(fq.TO_CUI, " | "))
fq.room("Port"); fq.command("run"); expect("")
-- Cui Cui
fq.gotPassword("6373"); fq.cuiDead(); wait(1)
expect("n | e | e | enter 6373")
feed("Vorrac enters a code into the computer."); expect("")
wait(2); expect("n | get all locker | wear battle | s | w | n")
-- then the walk to the Engine Hatch: one move per room
feed("Obvious exits:"); wait(0.5); expect("n")
-- the card lying in a room on the way: search and pick it up there, then walk on
feed("Obvious exits:"); feed("Engine Module Access Card was carelessly left here. (hidden)"); fq.cardSpotted()
wait(0.5); expect("search")
feed("After searching around you managed to uncover Engine Module Access Card!"); expect("get card | n")
fq.gotCard(); assert(fq.haveCard)
for _ = 1, 40 do feed("Obvious exits:"); wait(0.5) end
expect(table.concat(fq.TO_ENGINE, " | ", 4))
fq.engineHatch(); expect("")               -- already holding the card: no trip downstairs
fq.engineerWantsCard(); expect("give engine engineer")
fq.haveCard = false; fq.cancel()
-- engine: fq go away from the Engine Hatch doesn't shout the passwords
fq.room("Port"); fq.command("go"); expect("")
fq.room("Gangway"); fq.exit("West", "Frieza's Spaceship: Elite Quarters"); fq.command("go"); expect("n"); fq.cancel()
fq.room("Engine Module"); fq.exit("West", "Frieza's Spaceship: Engine Hatch"); fq.command("go"); expect("w")
fq.leg = nil
-- Engine search
fq.engineHatch(); expect(PW)
feed(OPEN); expect("d | search")
feed("You search around the area, but fail to find anything."); expect("s | search")
feed("After searching around you managed to uncover Engine Module Access Card!")
expect("get card | n | " .. PW)
feed(OPEN); expect("u")
fq.engineHatch(); expect("")       -- repeated room line ignored
fq.engineerWantsCard(); expect("give engine engineer")
fq.gotUniform(); expect("wear engineer | pursue steering")
-- Steering: no clan, straight down
fq.arrived("Steering Specialist"); expect("s | e")
fq.technicianAsks(); expect(PW)
feed(OPEN); expect("d | s | e | repair")
fq.steeringOnline(); expect("w | n | " .. PW); feed(OPEN); expect("u")
fq.steeringDone(); expect("pursue dying")
fq.dyingMan(); fq.dodoriaNamed(); fq.dodoriaHere(); expect("say revenge | pursue dodoria | ss dodoria")
fq.avenged(); expect("pursue communications")
fq.arrived("Communications Specialist"); expect("n | e | " .. PW); feed(OPEN); expect("d | s | e")
fq.officerAsks(); expect("give dying comm")
fq.needPower(); expect("w | n | " .. PW); feed(OPEN); expect("u | pursue power")
fq.room("Power Module"); fq.exit("North", "Frieza's Spaceship: Power Module")
fq.arrived("Power Specialist"); expect("s | w | " .. PW); feed(OPEN); expect("d | n | e")
fq.powerDone(); expect("w | s | " .. PW); feed(OPEN); expect("u | pursue communications")
fq.arrived("Communications Specialist"); expect("n | e | " .. PW); feed(OPEN); expect("d | s | e")
fq.officerAsks(); expect("give crum comm")
for _ = 1, 4 do fq.zarbonAsks() end; expect("say surrender | say surrender | say surrender | say surrender")
fq.duplicates(); fq.zarbonDead(); expect("ss zarbon | get all | d")
fq.bridgeCard(); assert(fq.stage == "done" and not fq.active)
print("\nSMOKE TEST PASSED")
