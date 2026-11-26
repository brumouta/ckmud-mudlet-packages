-- cumber: Rusk's containment assignment. Run from the repo root: lua tests/cumber_test.lua
local now, id, timers, inbox, sent = 0, 0, {}, {}, {}
local respond
function send(c) sent[#sent + 1] = c; if respond then respond(c) end end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
local function say(l) inbox[#inbox + 1] = l end
local function pump() while #inbox > 0 do cumber.line(table.remove(inbox, 1)) end end
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
dofile("packages/Cumber/src/Cumber.lua")

local n, w, e = cumber.parseCard("Card 3 calls for west 4 load units and east 15. The workshop rig has independent zero-to-five dials.")
ok(n == 3 and w == 4 and e == 15, "reads a card")
local wn, en = cumber.notches(4, 15)
ok(wn == 2 and en == 5, "card 3: west notch 2, east notch 5")
ok(cumber.notches(5, 12) == nil and cumber.notches(12, 3) == nil, "odd or too-big loads are refused")

-- a model of the containment level, exits and lines from the game log
local MAP = {
  ["Guard Withdrawal Post"] = { e = "Evacuation Stair", w = "First Restraint Gate" },
  ["Evacuation Stair"] = { w = "Guard Withdrawal Post", d = "Evacuation Landing" },
  ["Evacuation Landing"] = { e = "Containment Records", u = "Evacuation Stair" },
  ["Containment Records"] = { n = "Suppressor Issue Room", e = "Suppression Control", s = "Western Suppressor Chamber", w = "Evacuation Landing" },
  ["Western Suppressor Chamber"] = { n = "Containment Records", e = "Western Feed Gallery", s = "Western Coil Access" },
  ["Western Coil Access"] = { n = "Western Suppressor Chamber", s = "Western Isolation Switch" },
  ["Western Feed Gallery"] = { n = "Suppression Control", e = "Inner Guard Passage", w = "Western Suppressor Chamber" },
  ["Inner Guard Passage"] = { n = "Coolant Return Chamber", e = "Observation Stair", s = "Abandoned Guard Room", w = "Western Feed Gallery" },
  ["Observation Stair"] = { n = "Eastern Feed Gallery", e = "Eastern Coil Access", w = "Inner Guard Passage" },
  ["Eastern Coil Access"] = { n = "Eastern Suppressor Chamber", s = "Eastern Isolation Switch", w = "Observation Stair" },
  ["Eastern Suppressor Chamber"] = { s = "Eastern Coil Access", w = "Eastern Feed Gallery" },
  ["Eastern Feed Gallery"] = { e = "Eastern Suppressor Chamber", s = "Observation Stair", w = "Coolant Return Chamber" },
  ["Coolant Return Chamber"] = { n = "Southern Cooling Walk", e = "Eastern Feed Gallery", s = "Inner Guard Passage", w = "Suppression Control" },
  ["Southern Cooling Walk"] = { n = "Cooling Pump Station", s = "Coolant Return Chamber", w = "Cooling Ring Entrance" },
  ["Cooling Pump Station"] = { s = "Southern Cooling Walk", w = "Northern Cooling Walk" },
  ["Northern Cooling Walk"] = { e = "Cooling Pump Station", s = "Cooling Ring Entrance", w = "Restraint Workshop" },
  ["Restraint Workshop"] = { n = "Broken Restraint Store", e = "Northern Cooling Walk", s = "Suppressor Issue Room" },
  ["Suppressor Issue Room"] = { n = "Restraint Workshop", e = "Cooling Ring Entrance", s = "Containment Records" },
}
local AT = {
  ["study containment"] = { "Containment Records", "The failures share a mistake: crews treated the west and east feeds as substitutes.", "The old containment records are not here." },
  ["read west plate"] = { "Western Coil Access", "The western service plate identifies the restraint circuit. On the workshop test coupler, each west notch supplies two load units.", "The western access plate is not here." },
  ["read east plate"] = { "Eastern Coil Access", "The eastern service plate identifies the aura circuit. On the workshop test coupler, each east notch supplies three load units.", "The eastern access plate is not here." },
  ["inspect cooling loop"] = { "Northern Cooling Walk", "The live cooling circuit is independent of both suppressor feeds.", "The northern cooling service point is not here." },
  ["vent coupler"] = { "Northern Cooling Walk", "You bleed the disconnected test hose into the catch basin until its inspection tube is clear.", "The protected venting point and catch basin are not here." },
}
local CARDS = { { 6, 12 }, { 10, 6 }, { 4, 15 } }
local here, card, dial, done, rivalOnce, flubOnce, paid
local function world(startCard, opts)
  opts = opts or {}
  here, card, dial, done, paid = "The dark expanse of space", startCard, {}, {}, false
  rivalOnce, flubOnce = opts.rival, opts.flub
  respond = function(c)
    if c == "crecall" then here = "Galactic Federation HeadQuarters"; say(here)
    elseif c == "leave" then assert(here == "Galactic Federation HeadQuarters", "leave outside the clan hall"); here = "space"; say("You fly up into the air."); say("Galactic Federation HeadQuarters")
    elseif c == "pursue rusk" then
      assert(here ~= "The dark expanse of space" or not opts.mustTravel, "pursue before going to space")
      if rivalOnce then rivalOnce = false; say("Turnip the Saiyan flies out of nowhere and attacks you!"); return end
      say("You begin tracking Chief Rusk's ki..."); here = "Guard Withdrawal Post"; say(here); say("You have successfully tracked down Chief Rusk!")
    elseif c == "de turnip" then say("Turnip the Saiyan is dead!  R.I.P.")
    elseif c == "say containment" then say("You say, 'containment'"); say("Chief Rusk says, ''Study containment' in the records room. 'Read west plate' and 'read east plate'...'")
    elseif c == "say coupler" then
      say("You say, 'coupler'")
      if card > 3 then paid = true; say("Chief Rusk says, 'Three load records, correctly reproduced without confusing the feeds. Here are 500,000 zenni and 40 tokens.'")
      else say("Chief Rusk says, 'Bring me a coupler that has passed all three cards.'") end
    elseif c == "look testcoupler" then
      if not done["study containment"] and card == 1 then say("'Study containment' in the records room before interpreting a quiet coil."); return end
      local k = CARDS[card]
      if k then say(string.format("Card %d calls for west %d load units and east %d. The workshop rig has independent zero-to-five dials.", card, k[1], k[2])) end
    elseif c:match("^calibrate (%a+) (%d)$") then
      local side, v = c:match("^calibrate (%a+) (%d)$")
      assert(here == "Restraint Workshop", "calibrate away from the rig")
      if flubOnce and card == 3 and side == "east" then v = "4"; flubOnce = false end  -- a slip: card 3 needs 5
      dial[side] = tonumber(v)
      say("You set the coupler's " .. side .. " dial to notch " .. v .. ". The rig remains unloaded until you 'loadtest coupler'.")
    elseif c == "loadtest coupler" then
      assert(done["vent coupler"] or card > 1, "load test before venting")
      local k = CARDS[card]
      if not (dial.west and dial.east) then say("Set both dials deliberately before applying a test load."); return end
      local W, E = dial.west * 2, dial.east * 3
      dial = {}
      if W ~= k[1] or E ~= k[2] then
        say(string.format("The rig reads west %d against %d, east %d against %d. The mismatched load is released safely. Begin again with card one; the live coils were never connected to this test.", W, k[1], E, k[2]))
        card = 1; return
      end
      if card == 3 then card = 4; say("The third load card holds within both reference marks. You unload the rig and attach the completed test strip. Rusk can now certify the containment assignment.")
      else say("Both measured loads match card " .. card .. ". You unload the rig and turn to card " .. (card + 1) .. "; set both dials again against its separate references."); card = card + 1 end
    elseif AT[c] then
      local a = AT[c]
      if here == a[1] then done[c] = true; say(a[2]) else say(a[3]) end
    elseif MAP[here] and #c <= 1 then
      local to = MAP[here][c]
      if to then here = to; say(here); say("Status:  Normal") else say("Alas, you cannot go that way...") end
    end
  end
end

world(1, { rival = true, flub = true, mustTravel = true })
here = "Somewhere on Earth"
LOG, sent = "", {}
cumber.command("start")
run(120)
local s = table.concat(sent, "|")
ok(s:find("^crecall|leave|pursue rusk"), "goes to space first: crecall, leave, then pursue")
ok(paid and here == "Guard Withdrawal Post", "assignment handed in to Rusk")
ok(done["study containment"] and done["read west plate"] and done["read east plate"] and done["inspect cooling loop"] and done["vent coupler"], "studied, read both plates, inspected and vented")
ok(s:find("pursue rusk|de turnip|pursue rusk|say containment|look testcoupler", 1, true), "rival on the pursue: fought, then Rusk pursued again")
ok(s:find("calibrate west 3|calibrate east 4|loadtest coupler|look testcoupler|calibrate west 5|calibrate east 2|loadtest coupler", 1, true), "cards 1 and 2 solved")
ok(select(2, s:gsub("calibrate west 3", "")) == 2 and select(2, s:gsub("calibrate east 4", "")) == 2, "a failed card 3 starts over at card 1")
ok(LOG:find("Load test failed", 1, true) and LOG:find("Containment assignment done", 1, true), "reports the retry and the reward")
ok(next(timers) == nil, "nothing left running")

-- coupler already on card 2: no prep, straight to the workshop (no travel)
cumber.command("travel", "off")
world(2)
LOG, sent = "", {}
cumber.command("start")
run(60)
ok(paid and not done["study containment"], "card 2 on the coupler: skips the prep")
ok(table.concat(sent, "|"):find("e|d|e|n|n|look testcoupler|calibrate west 5|calibrate east 2", 1, true), "walks straight to the rig")

-- a fresh coupler: look testcoupler says to study first, so the prep is done
world(1)
LOG, sent = "", {}
cumber.command("start")
run(120)
s = table.concat(sent, "|")
ok(paid and done["study containment"] and done["vent coupler"], "fresh coupler ('Study containment' first): does the prep, then the cards")
ok(select(2, s:gsub("say coupler", "")) == 1, "never asks Rusk for a coupler, only hands it in")

-- just the rig
world(1); here = "Restraint Workshop"; done["vent coupler"] = true; done["study containment"] = true
LOG, sent = "", {}
cumber.command("solve")
run(30)
ok(card == 4 and LOG:find("All three cards passed", 1, true), "cumber solve: all three cards at the rig")
cumber.command("stop")
ok(next(timers) == nil, "cumber stop cleans up")

cumber.command("travel", "crecall;leave")
-- can't find Rusk
respond = function(c) if c == "pursue rusk" then say("You sense no ki.") end end
LOG = ""
cumber.command("start"); run(15)
ok(LOG:find("Can't sense Rusk", 1, true) and next(timers) == nil, "no Rusk in range: says where to go and stops")
print("\ncumber: ALL PASSED")
