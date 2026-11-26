-- fus: the West Capital fusion questline, end to end against a model of the game built from the
-- logs. Run from the repo root: lua tests/fusionquest_test.lua
local now, id, timers, inbox, sent = 0, 0, {}, {}, {}
local respond
function send(c) sent[#sent + 1] = c; if respond then respond(c) end end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
local function say(l) inbox[#inbox + 1] = l end
local function pump() while #inbox > 0 do fus.line(table.remove(inbox, 1)) end end
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
dofile("packages/FusionQuest/src/FusionQuest.lua")

-- every walk the helper will make, in order: the model checks each move against it
local moves = {}
for _, st in ipairs(fus.STAGES) do
  for _, s in ipairs(st[3]) do if s.go and #s.go <= 1 then moves[#moves + 1] = { dir = s.go, room = s.room, stage = st[1] } end end
end
local cursor, combat, enemy, here = 0, false, nil, "Kame House"
local count = { crate = 0, bench = 0, androids = 0, k = 0 }
local soldierDone, path, zeno, drill, kai = false, {}, false, nil, nil
local itFails = 0   -- how many instant transmissions to King Kai fail before one works
local function prompt()
  say("[Time: 12:00]")
  if combat then say("[Target: " .. combat .. "] [Rage: 0%]") end
  say("[Kaioken: 120/120 ] ")
  say("[Pl: 152,155,348,008 100% | Ki: 100% | Fatigue: 0%] [SP] [FLY][1/39007x G]")
end
local function room(name, ...)
  here = name
  say(name); say("Status:  Normal"); say("Gravity: Normal    Regen: Normal")
  for _, l in ipairs({ ... }) do say(l) end
  prompt()
end
local ENEMY = {  -- keyword -> { death line, room it waits in }
  courier = "a nervous courier is dead!  R.I.P.", foreman = "the Bay 9 foreman is dead!  R.I.P.",
  drone = "a Tuffle war drone is dead!  R.I.P.", turles = "Ghost Turles is dead!  R.I.P.",
  slug = "Ghost Lord Slug is dead!  R.I.P.", cooler = "Ghost Cooler is dead!  R.I.P.",
  frieza = "Ghost Frieza is dead!  R.I.P.", hatchiyack = "Full Power Hatchiyack is dead!  R.I.P.",
}
local SPAWN = {
  ["Market Stairs Lane"] = { "courier", "A skinny courier with a satchel under his arm comes up the market stairs and freezes." },
  ["Warehouse Bay 9"] = { "foreman", "The Bay 9 foreman chews a cigar beside the freight lift." },
  ["Generator Chamber"] = { "drone", "Something clicks awake beside the machine: a spider legged war drone of riveted steel." },
  ["Valve Room, First Floor"] = { "turles", "He stands between you and the valve. Put him down, then shut the valve." },
  ["Valve Room, Second Floor"] = { "slug", "He stands between you and the valve. Put him down, then shut the valve." },
  ["Valve Room, Third Floor"] = { "cooler", "He stands between you and the valve. Put him down, then shut the valve." },
  ["Valve Room, Fourth Floor"] = { "frieza", "He stands between you and the valve. Put him down, then shut the valve." },
  ["The Machine Floor"] = { "hatchiyack", "Hatchiyack's head turns. It has found you." },
}
local DRILL = { gravity = { "point", "swing", "point", "step left", "step left", "point" },
                hangar = { "step left", "step left", "step right", "step left", "point", "point", "point", "point" } }
local PURSUE = {
  doberman = function()
    if fus.stage == "doberman" then
      say("Chief Doberman stands, which he does not do for many people, stamps your case file CLOSED, keeps it with the manifest.")
    end
    room("Chief's Office", "Chief Doberman glares at a corkboard of reports.")
    say("You have successfully tracked down Chief Doberman!")
  end,
  bulma = function()
    if fus.stage == "gas" and count.vial then say("Bulma takes the vial, the scrap and the mask, holds the scrap up to the light, and goes very quiet.") end
    room("Bulma's Workshop", "Bulma frowns at a schematic, a screwdriver behind one ear.")
    say("You have successfully tracked down Bulma!")
  end,
  ["dr briefs"] = function() room("Dr. Briefs' Laboratory"); say("You have successfully tracked down Dr. Briefs!") end,
  raichi = function()
    say("The purple haze in the doorway closes your throat. You back away, coughing.")
    room("Tongari Square"); say("Your path is blocked. You lose the trail.")
  end,
  king = function()
    say("King Kai exclaims, 'Somen sent you? The dance! Timing is my art. But first: why did the Saiyan bring a ladder to the fight? To reach the next level!'")
    say("King Kai says, '...Well? Go on. Laugh.'")
    room("King Kai's Living Room"); say("You have successfully tracked down King Kai!")
  end,
  vegeta = function() room("Gravity Room West"); say("You have successfully tracked down Vegeta!") end,
}
local AT = {   -- command -> room it has to be done in, and what it prints
  ["say case"] = { "Chief's Office", "The chief hands you a thin case file." },
  ["free engineer"] = { nil, "You snap the chain off the bench." },
  ["pull breaker"] = { "The Core", "Vorricer hauls the main breaker down. Every light in the factory flickers." },
  ["say sixteen"] = { "Bulma's Workshop", "Bulma says, 'I want him. Three crates of his parts are still down there.'" },
  ["say air"] = { nil, nil },
  ["read monitor"] = { nil, "You thumb the little screen awake. AIR QUALITY POOR." },
  ["search"] = { nil, "Under a tarp stamped with a red star you find Sixteen's arm assembly, heavy and cold." },
  ["say gas"] = { "Bulma's Workshop", "Bulma pushes a mask capsule into your hands and snaps it on your face before you can argue." },
  ["collect sample"] = { "Generator Chamber", "You cap a vial of the purple gas at the vent." },
  ["throw 211 n"] = { "Tongari Square", "You thumb the button and throw. The capsule pops into a cloud of clean, cold air." },
  ["watch"] = { "Blueprint Archive", "A small capsule earpiece is taped under the screen, with a note in Bulma's handwriting." },
}
respond = function(c)
  -- travel: recall, the Zeno Button, the vortex, the survey
  if c == "recall" then zeno = false; room("King Kai's Planet"); return end
  if c == "press button" then zeno = true; room("A Grand Atrium"); return end
  if zeno and (c == "s") then return room(here == "A Grand Atrium" and "A mysterious room" or "A mysterious room") end
  if c == "enter vortex" then zeno = false; say("You step through the portal."); room("a grassy field"); return end
  if c == "fly" then if here == "King Kai's Planet" and not path.flying then path.flying = true; say("You fly up into the air.") else say("You fly up high above the area!"); room("North Kai Planet") end return end
  if c == "survey" then
    say("Nearby Locations:")
    if here == "North Kai Planet" then say(" 5. Otherworld Tournament Arena, go South")
    else say(" 5. Majerska's Cursed Canopy, go North"); say("21. West Capital, go North") end
    return
  end
  if c == "survey 21 fly" then say("- West Capital, go North."); room("West Capital"); say("You land on the ground in front of West Capital."); return end
  if c == "survey 5 fly" then room("Otherworld Tournament Arena"); say("You land on the ground in front of Otherworld Tournament Arena."); return end
  if c == "enter" then
    if here == "West Capital" then room("West Capital Gate") return end
    if here == "Otherworld Tournament Arena" then
      room("Arena Sidewalk", "Somen the Metamoran dance master says, 'The steps are easy. The timing is not, and timing is King Kai's art.'")
    end
    return
  end
  local function kaiArrives()
    say("King Kai exclaims, 'Somen sent you? The dance! Timing is my art. But first: why did the Saiyan bring a ladder to the fight? To reach the next level!'")
    say("King Kai says, '...Well? Go on. Laugh.'")
    room("King Kai's Living Room")
  end
  if c == "focus 'instant' king kai" then
    say("Okay.")
    if itFails > 0 then itFails = itFails - 1; say("You failed."); prompt(); return end
    say("You touch two fingers to your forehead and disappear suddenly."); kaiArrives(); return
  end
  if c == "crecall" then return room("Capsule Corp Ship") end
  if c == "leave" then room("Outer Space", "You can 'land' here."); return end
  if c == "pursue king kai" then
    assert(here == "Outer Space", "pursue king kai from " .. here)
    kaiArrives(); say("You have successfully tracked down King Kai!"); prompt(); return
  end
  if c:match("^pursue ") then
    local who = c:sub(8)
    if fus.stage == "gas" and who == "bulma" and count.vial == nil and cursor > 0 then count.vial = false end
    assert(PURSUE[who], "pursue " .. who); PURSUE[who](); prompt(); return
  end
  -- fights
  local kw = c:match("^k (.+)$")
  if kw then
    count.k = count.k + 1
    if kw == "android" then
      assert(here == "The Core", "androids away from the core")
      local names = { "Android 15", "Android 14", "Super Android 13" }
      count.androids = count.androids + 1
      local n = names[count.androids]
      if not n then say("They aren't here."); return end
      combat = n; prompt()
      tempTimer(3, function() combat = false; say(n .. " is dead!  R.I.P."); prompt() end)
      return
    end
    if enemy ~= kw then say("They aren't here."); return end
    combat = kw; prompt()
    tempTimer(4, function() combat = false; enemy = nil; say(ENEMY[kw]); prompt() end)
    return
  end
  -- the drills and King Kai
  if c == "laugh" then say("King Kai says, 'HA! You laughed! Nobody laughs! All right, all right, I will teach you. Walk out and back in when you are ready, and I will call the steps.'"); return end
  if drill then
    local want = drill.calls[drill.i]
    assert(c == want, "drill: sent " .. c .. ", wanted " .. tostring(want))
    say(c:match("(%a+)$") .. "!")
    drill.i = drill.i + 1
    if drill.calls[drill.i] then say("Next: " .. drill.calls[drill.i])
    else say("Fuuu... sion... HA!"); say(drill.finish); drill = nil end
    return
  end
  if c == "drill" then
    local calls = assert(DRILL[fus.stage], "drill in stage " .. fus.stage)
    assert(here == (fus.stage == "gravity" and "Gravity Room South" or "Capsule Corp Hangar"), "drill in " .. here)
    drill = { calls = calls, i = 1, finish = fus.stage == "gravity" and "Bulma, in your ear: Good. Now the hangar. Sixteen is waiting, and so am I."
                                                     or "Bulma, in your ear: That is it. That is the dance. Now go and do it with somebody real." }
    say(#calls .. " calls, 4 seconds each. First: " .. calls[1]); prompt()
    return
  end
  if kai then
    assert(c == kai.calls[kai.i], "king kai: sent " .. c); kai.i = kai.i + 1
    say(c:match("(%a+)$") .. "!")
    if not kai.calls[kai.i] then say("Fuuu... sion... HA!"); say("King Kai, faintly: Not bad! Not bad at all."); kai = nil end
    return
  end
  -- Bulma's bench: out and back in
  if fus.stage == "bench" and (c == "e" or c == "w") then
    if c == "e" then return room("Capsule Corp Residence Hall") end
    count.bench = count.bench + 1
    room("Bulma's Workshop", "Bulma frowns at a schematic, a screwdriver behind one ear.")
    if count.bench == 1 then say("Bulma says, 'He is on my bench. Walk back in in about 3 minutes.'")
    elseif count.bench == 2 then say("On Bulma's bench a huge android with a red mohawk opens his eyes, looks at the ceiling.")
    else say("Bulma holds up a capsule with 211 painted on it in her father's small neat hand.") end
    return
  end
  if fus.stage == "kaikai" and (c == "s" or c == "n") then
    if c == "s" then return room("King Kai's House") end
    room("King Kai's Living Room")
    say("King Kai exclaims, 'Listen once, then do it back to me in order, five seconds a step: point, point, step left, swing. Go!'")
    kai = { calls = { "point", "point", "step left", "swing" }, i = 1 }
    return
  end
  -- quest commands
  if c == "inspect crate" then
    count.crate = count.crate + 1
    say("You peel back a price sticker. Under it is an older label, and under that, stamped small and neat, a red star.")
    if count.crate == 3 then say("The same red star, all three crates. A stall keeper sees you looking.") end
    return
  end
  if c == "shut panel" then
    assert(here:find("Control Booth"), "shut panel in " .. here)
    if here == "Line A Control Booth" then say("You punch in the engineer's birthday."); say("All three lines are dead.")
    elseif here == "Line B Control Booth" then say("You punch in Bulma's birthday.")
    else say("Four zeroes. The line shudders, coughs and dies.") end
    return
  end
  if c == "shut valve" then
    assert(here:find("^Valve Room") and enemy == nil, "shut valve in " .. here .. " with " .. tostring(enemy))
    say(here == "Valve Room, Fourth Floor" and "The last valve closes. The way to the machine floor is open." or "The valve shuts. The stairs up clear.")
    return
  end
  if c == "listen" then
    say("You stand beside Sixteen and listen.")
    if here == "Dream Land Fountain Plaza" then say("Android 16 says, 'I remember where it is. Gero's last lab.'") end
    say("Sixteen nods once and walks off toward somewhere with more birds.")
    return
  end
  if c == "say air" then
    if here == "Bulma's Workshop" then say("Bulma says, 'Ask him about the air; his lab is at the end of the west gallery.'")
    else say("Dr. Briefs says, 'Read each one and the numbers will come straight here.'") end
    return
  end
  if c == "collect sample" then count.vial = true end
  if AT[c] then
    local a = AT[c]
    assert(not a[1] or here == a[1], c .. " in " .. here)
    if a[2] then say(a[2]) end
    return
  end
  -- a move: has to be the next walk, and not in the middle of a fight
  if #c <= 1 then
    assert(not combat, "moved " .. c .. " while fighting")
    cursor = cursor + 1
    local m = moves[cursor]
    assert(m and m.dir == c, "move " .. cursor .. ": sent " .. c .. ", wanted " .. (m and m.dir or "none") .. " (" .. fus.stage .. ")")
    if m.room == "Bulma's Workshop" and fus.stage == "report" then
      room("Bulma's Workshop", "Bulma says, 'You are back! And in one piece! Sit. Tell me everything.'",
           "Bulma says, 'Dad's Blueprint Archive, through the west gallery: watch the recording.'")
    elseif m.room == "Tongari Tower Lobby" then
      room("Tongari Tower Lobby")
    elseif m.room == "Lift Bottom" and not soldierDone then
      soldierDone = true
      combat = "a Red Ribbon soldier"
      room("Lift Bottom", "A Red Ribbon soldier patrols with a rifle across his chest.")
      tempTimer(5, function() combat = false; say("a Red Ribbon soldier is dead!  R.I.P."); prompt() end)
    else
      local sp = SPAWN[m.room]
      if sp then enemy = sp[1] end
      room(m.room, sp and sp[2] or nil)
    end
    return
  end
  error("unexpected command: " .. c)
end

fus.command("stage", "case")
fus.command("start")
run(4000)
local s = table.concat(sent, "|")
ok(fus.stage == "done", "every stage done (stage: " .. fus.stage .. ")")
ok(cursor == #moves, "every walk made: " .. cursor .. " of " .. #moves)
ok(s:find("^recall|press button|s|s|enter vortex|survey|survey 21 fly|enter|pursue doberman|say case"), "travels to West Capital, takes the case")
ok(count.crate == 3, "three crates inspected")
ok(s:find("k courier", 1, true) and s:find("k foreman", 1, true), "courier and foreman fought")
ok(s:find("pull breaker|k android", 1, true) and count.androids == 3, "breaker pulled, all three androids fought (re-attacks between them)")
ok(s:find("say sixteen|say air", 1, true), "Bulma asked about Sixteen and the air")
ok(select(2, s:gsub("read monitor", "")) == 4 and select(2, s:gsub("search", "")) == 3, "four monitors read, three crates searched")
ok(s:find("say gas", 1, true) and s:find("k drone|collect sample", 1, true), "mask, drone, sample")
ok(count.bench == 3, "Bulma's bench: back in until Capsule 211 (3 visits)")
ok(select(2, s:gsub("listen", "")) == 3, "listened with Sixteen three times")
ok(s:find("throw 211 n|n|u", 1, true), "Capsule 211 at the tower door, then in")
for _, g in ipairs({ "turles", "slug", "cooler", "frieza" }) do ok(s:find("k " .. g .. "|shut valve", 1, true), g .. " beaten, valve shut") end
ok(s:find("k hatchiyack", 1, true), "Hatchiyack fought")
ok(s:find("pursue dr briefs|e|n|watch", 1, true), "Goku's recording watched")
ok(s:find("recall|fly|fly|survey|survey 5 fly|enter", 1, true), "flies to the Otherworld Tournament Arena")
ok(s:find("enter|focus 'instant' king kai|laugh|s|n|point|point|step left|swing", 1, true), "King Kai: instant transmission, laugh, out and back in, the dance in order")
ok(s:find("pursue vegeta|e|drill|point|swing|point|step left|step left|point", 1, true), "gravity drill answered call by call")
ok(s:find("drill|step left|step left|step right|step left|point|point|point|point", 1, true), "hangar drill answered call by call")
ok(LOG:find("Fuse with another player", 1, true), "ends telling you to fuse with another player")
ok(next(timers) == nil, "nothing left running")

-- King Kai when instant transmission keeps failing: space, then pursue
fus.command("stage", "kaikai")
itFails, sent, LOG = 2, {}, ""
local model = respond
respond = function(c) if fus.stage == "kaikai" then model(c) end end   -- just this stage; the next one gets no answers
fus.command("start"); run(120)
respond = model
s = table.concat(sent, "|")
ok(s:find("^focus 'instant' king kai|focus 'instant' king kai|crecall|leave|pursue king kai|laugh|s|n|point", 1, false) ~= nil, "two failed instant transmissions, then crecall, leave, pursue king kai, the dance")
ok(fus.stage == "gravity", "on to the gravity room after King Kai (stage: " .. fus.stage .. ")")
fus.stop(true)

-- stop and resume
fus.command("stage", "archive")
respond = function(c) if c == "pursue dr briefs" then say("You can't seem to sense Dr. Briefs's ki from here.") end end
LOG = ""
fus.command("start"); run(5)
ok(LOG:find("Can't find dr briefs", 1, true) and fus.stage == "archive" and next(timers) == nil, "a failed pursue stops and keeps the stage")
fus.command("stage", "nope")
ok(LOG:find("No stage 'nope'", 1, true), "unknown stage refused")
print("\nfus: ALL PASSED")
