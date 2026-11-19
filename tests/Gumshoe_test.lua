-- gum: the case read from a real Thanksgiving case, the map and keypad, and a whole case run
-- in a fake house that answers like the game did. Run from the repo root: lua tests/Gumshoe_test.lua
local now, timers, nextId, sent = 0, {}, 0, {}
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
local function feed(lines) for _, l in ipairs(lines) do gum.line(l) end end

-- The real lines, by section
local S, cur = {}, nil
for l in io.lines("tests/fixtures/gumshoe.log") do
  local name = l:match("^## (.+)$")
  if name then cur = name; S[cur] = {} elseif cur then table.insert(S[cur], l) end
end

dofile("packages/Gumshoe/src/Gumshoe.lua")
local G = gum

-- The map ------------------------------------------------------------------------------
local function dirs(p) local o = {} for _, s in ipairs(p) do o[#o + 1] = s.dir end return table.concat(o) end
ok(dirs(G.path("Front Steps", "Attic")) == "nnnnnwwuu", "Front Steps to the Attic: up the west stairs")
ok(dirs(G.path("Menagerie Yard", "Infirmary")) == "eeennneeun", "Menagerie Yard to the Infirmary: up the east stairs")
ok(G.path("Garden Hall", "Underground Lab") == nil, "the lab is sealed until the keypad opens it")
G.open.lab = true
ok(dirs(G.path("Garden Hall", "Underground Lab")) == "nd", "...then it's north and down")
G.newCase()
for r, exits in pairs(G.EXITS) do
  for _, e in ipairs(exits) do
    local back = false
    for _, b in ipairs(G.EXITS[e.to]) do if b.to == r then back = true end end
    assert(back, r .. " -> " .. e.to .. " has no way back")
  end
end
ok(true, "every exit has a way back")

-- The keypad ----------------------------------------------------------------------------
local P = { { name = "Mrs. Briefs", digit = "6" }, { name = "Trunks", digit = "4" }, { name = "Dr. Briefs", digit = "2" }, { name = "Bulma", digit = "3" } }
ok(G.codeFromPortraits(P, "Right to left, as they hang.") == "3246", "right to left: 3246 (the code that opened the lab)")
ok(G.codeFromPortraits(P, "Left to right, as they hang.") == "6423", "left to right: 6423")
ok(G.codeFromPortraits(P, "Oldest to youngest.") == "2634", "oldest to youngest: Dr. Briefs, Mrs. Briefs, Bulma, Trunks")
ok(G.codeFromPortraits(P, "Youngest to oldest.") == "4362", "youngest to oldest")

-- Reading the real case -------------------------------------------------------------------
feed(S.intro)
ok(G.case.scene == "Menagerie Yard" and #G.guests == 12 and G.unquestioned["Mr. Popo"], "intro: scene, the twelve guests")
feed(S["notebook-start"])
ok(G.case.minutes == 60 and G.evTotal == 6 and G.analyses == 1, "notebook: time left, evidence count, one analysis")
local n = 0 for _ in pairs(G.unsearched) do n = n + 1 end
ok(n == 22 and G.unsearched["Dr. Briefs' Study"] and G.unsearched["Pond and Aviary"] and G.unsearched.Attic,
  "notebook: the 22 rooms still to search, Study named as the room")
ok(G.unquestioned["Android 18"] and not G.unquestioned.Krillin, "notebook: who's still to question")
ok(G.open.lab == false and G.open.gravity == false and G.open.suite == false, "notebook: all three rooms sealed")
ok(G.secrets.Yamcha and not G.secrets.Yamcha.confronted, "notebook: Yamcha's secret waiting")
ok(#G.weaponsAll == 6 and G.weaponsAll[3] == "Lights Out Capsule", "notebook: the weapon list")
feed(S.guests)
ok(G.traits["Master Roshi"].hair == "not dark" and G.traits.Mai.ki == "quiet" and G.witnesses["Mr. Popo"] and G.witnesses["Android 18"],
  "guests: looks and the four witnesses")
local sus = G.suspects()
ok(#sus == 8 and not G.witnesses[sus[1]], "eight suspects")
feed(S["first-statements"]); feed(S.chart); feed(S.logs)
ok(G.statements[12].Yamcha.room == "Dining Room" and #G.statements[12].Yamcha.with == 3, "statements: Yamcha's first midnight story")
ok(G.chart[12]["Mr. Popo"] and G.chart[9].Gohan, "the seating chart")
ok(G.log[12]["Dining Room"] == 3 and G.log[11]["Family Lounge"] == "broken", "the door log, broken sensors too")
local rank, tag = G.alibi("Launch", 9)
ok(tag == "LIED", "Launch at nine: Dende names only Roshi in the Grand Hall")
rank, tag = G.alibi("Yamcha", 12)
ok(tag == "LIED", "Yamcha at midnight: Popo and the chart leave him out of the Dining Room")
rank, tag = G.alibi("Tien", 12)
ok(tag == "LIED", "Tien at midnight too, before he confesses")
rank, tag = G.alibi("Master Roshi", 12)
ok(tag == "seen", "Roshi at midnight: Android 18 saw him")

feed(S.found)
ok(G.evFound == 6 and G.evidence[3].text:find("ki sense"), "the six pieces of evidence")
ok(G.secrets.Tien.room == "Robot Workshop" and G.secrets.Launch.phrase == "never trust a stand in" and G.phrase == "never trust a stand in",
  "secrets: where to confront, and the phrase on the back")
feed(S.inspect)
ok(G.window[11] and G.window[12] and not G.window[10] and #G.weaponCands == 2 and G.weaponCands[2].room == "Family Lounge",
  "the remains: eleven to midnight, Lights Out Capsule or Dream Ray")
feed(S.portraits)
ok(G.code == "3246", "the portraits: lab code 3246")

-- Before the confessions: midnight or eleven, two weapons
local r = G.solve()
ok(r.suspect == "Yamcha", "first read: Yamcha")
feed(S.confront)
ok(G.secrets.Tien.confronted and G.secrets.Launch.confronted and G.secrets.Yamcha.confronted, "the confessions mark each secret")
feed(S["final-statements"]); feed(S["notebook-end"]); feed(S.accuse)
ok(G.statements[9].Launch.first == "Grand Hall" and G.statements[12].Yamcha.room == "Family Lounge", "statements after the confessions")
ok(G.weapon == "Dream Ray" and G.quiet[11], "notebook: the Dream Ray, and all quiet at eleven")
ok(table.concat(G.akw.suspects, " ") == "yamcha roshi launch mai satan tien gohan piccolo" and #G.akw.weapons == 6,
  "accuse: the words it takes")
rank, tag = G.alibi("Tien", 12)
ok(tag == "fits", "Tien's confession fits: Mai and Gohan, and three heads in the Grand Hall")
rank, tag = G.alibi("Yamcha", 12)
ok(tag == "LIED", "Yamcha's confession doesn't: Krillin and Dende never name him")
r = G.solve()
ok(r.suspect == "Yamcha" and r.time == 12 and r.weapon == "Dream Ray", "solve: Yamcha, Dream Ray, midnight")
ok(r.line == "accuse yamcha with dream at midnight", "the accusation: " .. tostring(r.line))
ok(r.analyze == 3, "the quiet-air clue is the one against Yamcha: analyze 3")
ok(r.plate == "Yamcha", "the cake clues disagree: plate Yamcha")
feed(S.analyze); feed(S.plate)
G.weighEvidence()
ok(G.evidence[3].state == "planted" and G.evidence[4].state == "ok", "#3 planted, so the scorch marks stand")
r = G.solve()
ok(G.traits.Yamcha.cake == "refused" and not r.plate and not r.analyze and r.sure, "after the lab and the plate: nothing left to check")
ok(r.rows[1].matches == 3, "Yamcha matches three clues: light tread, flaring ki, dark hair")
LOG = ""; G.report(r)
ok(LOG:find("Solved: accuse yamcha with dream at midnight", 1, true), "report says it")
sent = {}; G.command("accuse")
ok(sent[1] == "accuse yamcha with dream at midnight", "gum accuse sends it")
feed(S.closed)
ok(LOG:find("Case closed: Perfect", 1, true), "case closed")

-- A whole case in a fake house -------------------------------------------------------------
-- Same guests, statements, log and evidence as the real case; gum run does everything.
G.newCase(); G.room = nil; sent = {}; LOG = ""
local H = {
  room = "Front Steps", entered = 0, lab = false, gravity = false, suite = false, flashlight = false,
  guests = { ["Entrance Hall"] = { "Mr. Popo" }, ["Sun Porch"] = { "Krillin" }, Cloakroom = { "Android 18" },
             ["Grand Hall"] = { "Yamcha" }, ["Family Lounge"] = { "Master Roshi" }, ["Dr. Briefs' Study"] = { "Gohan" },
             ["Robot Workshop"] = { "Tien", "Launch" }, ["Garden Hall"] = { "Dende" }, Conservatory = { "Piccolo", "Mai" },
             ["Menagerie Yard"] = { "Mr. Satan" } },
  hidden = {
    ["Underground Lab"] = { "You find fresh scorch marks, the wallpaper still smoking. (evidence #4)" },
    ["Garden Hall"] = { "You find a patch of air so still your ki sense slides off it. (evidence #3)" },
    Conservatory = { "You find a fork with a smear of birthday frosting. (evidence #2)" },
    ["Bulma's Suite"] = { "You find a trail of light, quick footprints through spilled punch. (evidence #1)" },
    Attic = { "You find an untouched slice of cake, the fork never lifted. (evidence #5)" },
    ["Gravity Chamber"] = { "You find a single dark hair caught on a splinter. (evidence #6)" },
    ["Grand Hall"] = { "Tucked out of sight: a love letter Yamcha wrote to himself. That belongs to Yamcha, in the Grand Hall: confront yamcha there." },
    Infirmary = { "Tucked out of sight: a love poem to Launch, signed with a little third eye. That belongs to Tien, in the Robot Workshop: confront tien there." },
    ["Robot Charging Bay"] = { { "Tucked out of sight: a wanted poster of Launch, blonde. That belongs to Launch, in the Robot Workshop: confront launch there.",
                                 'Scribbled on the back: "never trust a stand in".' } },
    ["Dining Room"] = { S.chart },
  },
  searchable = {}, searched = {}, questioned = {}, confronted = {}, inspected = false, logs = 0,
  darkSearches = 0, blocked = 0, events = {},
}
for _, r2 in ipairs({ "Grand Hall", "Portrait Gallery", "Garden Hall", "Cloakroom", "Dining Room", "Family Lounge", "Kitchen",
  "Dr. Briefs' Study", "Covered Walkway", "Robot Workshop", "Service Yard", "Menagerie Yard", "East Corridor", "West Corridor",
  "Robot Charging Bay", "Conservatory", "Hangar", "Pond and Aviary", "Dinosaur Paddock", "Infirmary", "Master Bedroom", "Attic" }) do
  H.searchable[r2] = true
end
local NAMES = { ["Dr. Briefs' Study"] = "Study" }
local function event(e) H.events[#H.events + 1] = e end
local function out(lines) tempTimer(0.1, function() feed(lines) end) end
local function arrive()
  H.entered = now
  local lines = { H.room, "Status:  NoQuit, NoRecall, NoPortal", "Obvious exits:" }
  for _, g in ipairs(H.guests[H.room] or {}) do lines[#lines + 1] = g .. " stands about, looking festive." end
  out(lines)
end
local function sealedText()
  return " [ ] 6. Sealed rooms: the lab " .. (H.lab and "open" or "locked (study portraits)") .. "; the Gravity Chamber " ..
    (H.gravity and "open" or "at 300G (shut gravity)") .. "; Bulma's Suite " .. (H.suite and "open" or "voice locked") .. "."
end
local function notebook()
  local found, ev = 0, {}
  for i = 1, 6 do if H["ev" .. i] then found = found + 1; ev[#ev + 1] = "      #" .. i .. " [unverified] " .. H["ev" .. i] end end
  local L = { "========================================", "GALACTIC PATROL, PARTY INCIDENT REPORT",
    "Case: Mrs. Briefs' stand-in smashed, Menagerie Yard", "Status: OPEN, 50 minutes left", "Difficulty: Normal",
    "Wrong accusations: 0 of 3. notebook commands lists every command.", "========================================", "Leads:",
    H.inspected and " [x] 1. When: between eleven and midnight; the party log says all was quiet at eleven." or " [ ] 1. When: inspect remains.",
    H.inspected and " [x] 2. Weapon: the Dream Ray, kept in the Family Lounge. notebook <time> shows who." or " [ ] 2. Weapon: inspect remains.",
    " [ ] 3. Physical evidence: " .. found .. " of 6 found. search the rooms; analyze <number> one in the lab (1 left)." }
  for _, e in ipairs(ev) do L[#L + 1] = e end
  local left = {}
  for r2 in pairs(H.searchable) do if not H.searched[r2] then left[#left + 1] = NAMES[r2] or r2 end end
  table.sort(left)
  if #left > 0 then
    L[#L + 1] = "      Not searched yet (" .. #left .. "), go there and search:"
    for i = 1, #left, 3 do
      local chunk = {}
      for j = i, math.min(i + 2, #left) do chunk[#chunk + 1] = left[j] end
      L[#L + 1] = "      " .. table.concat(chunk, ", ") .. (i + 2 >= #left and "." or ",")
    end
  else
    L[#L + 1] = "      Searched: every open room."
  end
  local nq = {}
  for _, g in ipairs(G.guests) do if not H.questioned[g] then nq[#nq + 1] = g end end
  L[#L + 1] = " [ ] 4. Statements: " .. (12 - #nq) .. " of 12."
  if #nq > 0 and #nq < 12 then L[#L + 1] = "      Not questioned yet: " .. table.concat(nq, ", ") .. "." end
  L[#L + 1] = sealedText()
  L[#L + 1] = " [ ] 7. Accuse: 9 of 4 findings."
  L[#L + 1] = "Weapons: Gravity Gauntlet, Battle Jacket Mk.0, Lights Out Capsule, Dream Ray, Hoi Poi Hornets, Capsule Taser."
  L[#L + 1] = "========================================"
  return L
end
local function statements(t)
  local block, which = {}, 0
  for _, l in ipairs(S["final-statements"]) do
    if l:find("^STATEMENTS ABOUT") then which = which + 1 end
    if which == t - 8 then block[#block + 1] = l end
  end
  table.insert(block, 1, "========================================")
  return block
end
local function section(name, pick)
  local o = {}
  for _, l in ipairs(S[name]) do if not pick or l:find(pick) then o[#o + 1] = l end end
  return o
end

respond = function(c)
  local dir = ({ n = 1, s = 1, e = 1, w = 1, u = 1, d = 1 })[c]
  if dir then
    for _, e in ipairs(G.EXITS[H.room]) do
      if e.dir == c then
        if e.to == "Underground Lab" and not H.lab then H.blocked = H.blocked + 1; return out({ "Alas, you cannot go that way..." }) end
        if e.to == "Gravity Chamber" and not H.gravity then H.blocked = H.blocked + 1; return out({ "Three hundred G pin you in the doorway." }) end
        if e.to == "Bulma's Suite" and not H.suite then H.blocked = H.blocked + 1; return out({ "The voice lock blinks red. say it here." }) end
        H.room = e.to
        return arrive()
      end
    end
    H.blocked = H.blocked + 1
    return out({ "Alas, you cannot go that way..." })
  end
  if c == "look" then return arrive() end
  if c == "search" then
    if H.gravity and not H.flashlight then H.darkSearches = H.darkSearches + 1; return out({ "It is too dark to search." }) end
    if now - H.entered < 1 then return out({ "You are still turning this room over." }) end
    if not H.searchable[H.room] then return out({ "Nothing is ever hidden in the " .. H.room .. "." }) end
    local items = H.hidden[H.room]
    if items and #items > 0 then
      local item = table.remove(items, 1)
      if type(item) == "string" then item = { item } end
      for _, l in ipairs(item) do
        local i, text = l:match("evidence #(%d)"), l:match("^You find (.-)%. %(")
        if i then H["ev" .. i] = text end
      end
      event("search " .. H.room)
      return out(item)
    end
    H.searched[H.room] = true
    event("searched " .. H.room)
    return out({ "Only dust and party streamers.", "This room is done for now. Your notebook lists the rest." })
  end
  local q = c:match("^question (%S+)$")
  if q then
    for _, g in ipairs(H.guests[H.room] or {}) do
      if G.keyword(g, {}) == q then H.questioned[g] = true; return out({ g .. " tells you, 'Here.'", 'At midnight: "Somewhere."' }) end
    end
    return out({ "Nobody by that name is here." })
  end
  local cf = c:match("^confront (%S+)$")
  if cf then
    event("confront " .. cf)
    for _, g in ipairs(H.guests[H.room] or {}) do
      if G.keyword(g, {}) == cf then H.confronted[g] = true; return out({ g .. " sees a secret and goes pale. \"Fine.\"", '"So that is where I really was:"' }) end
    end
  end
  if c == "notebook" then return out(notebook()) end
  if c == "notebook guests" then return out(S.guests) end
  local t = tonumber(c:match("^notebook (%d+)$") or "")
  if t then return out(statements(t)) end
  local lt = c:match("^read log (%a+)$")
  if lt then
    H.logs = H.logs + 1
    local o, on = {}, false
    for _, l in ipairs(S.logs) do
      if l:find("^Garter") then on = l:find("for " .. lt .. ",") ~= nil end
      if on then o[#o + 1] = l end
    end
    return out(o)
  end
  if c == "inspect remains" and H.room == "Menagerie Yard" then H.inspected = true; return out(S.inspect) end
  if c == "study portraits" and H.room == "Portrait Gallery" then return out(S.portraits) end
  if c == "press 3246" and H.room == "Lab Vestibule" then H.lab = true; H.searchable["Underground Lab"] = true
    return out({ "The keypad chimes, and the lab door clicks open for you." }) end
  if c == "shut gravity" and H.room == "Robot Charging Bay" then H.gravity = true; H.searchable["Gravity Chamber"] = true; event("shut")
    return out({ "You haul the red lever down. The Gravity Chamber winds down with a groan, and every light in the house dies with it." }) end
  if c == "take flashlight" and H.room == "Hangar" then H.flashlight = true; event("flashlight")
    return out({ "You take a flashlight from the rack. Searching in the dark is possible now." }) end
  if c == "say never trust a stand in" and H.room == "Upper Landing East" then H.suite = true; H.searchable["Bulma's Suite"] = true
    return out({ "You say, 'never trust a stand in'", "The voice lock chimes green. Bulma's Suite is open to you." }) end
  if c == "accuse" then return out(S.accuse) end
  if c == "plate yamcha" and H.room == "Kitchen" then event("plate"); return out(S.plate) end
  if c == "analyze 3" and H.room == "Underground Lab" then event("analyze"); return out(S.analyze) end
end

feed(S.intro)
G.run()
local spent = 0
while G.running and spent < 3600 do wait(5); spent = spent + 5 end
ok(not G.running and spent < 3600, ("the run finished (%d virtual seconds, %d commands)"):format(spent, #sent))
ok(H.blocked == 0, "never walked into a wall or a sealed door")
ok(H.darkSearches == 0, "never searched in the dark: the flashlight came first")
local all = true
for r2 in pairs(H.searchable) do if not H.searched[r2] then all = false; print("   not searched: " .. r2) end end
ok(all and H.searched["Underground Lab"] and H.searched["Gravity Chamber"] and H.searched["Bulma's Suite"],
  "every room searched to the end, the three sealed rooms included")
local nq = 0 for _, g in ipairs(G.guests) do if not H.questioned[g] then nq = nq + 1 end end
ok(nq == 0, "all twelve guests questioned")
ok(H.inspected and H.logs == 4, "remains inspected, the door log read for all four chimes")
ok(H.confronted.Yamcha and H.confronted.Tien and H.confronted.Launch, "the three secrets confronted")
local lastSearch, firstConfront, shut, light
for i, e in ipairs(H.events) do
  if e:find("^search") then lastSearch = i end
  if e:find("^confront") and not firstConfront then firstConfront = i end
  if e == "shut" then shut = i end
  if e == "flashlight" then light = i end
end
ok(firstConfront > lastSearch, "confronting only after every search")
ok(shut and light == shut + 1, "shut gravity, then straight to the flashlight")
local has = {} for _, e in ipairs(H.events) do has[e] = true end
ok(has.analyze and has.plate, "analyzed #3 and plated Yamcha before naming him")
ok(G.result and G.result.line == "accuse yamcha with dream at midnight" and G.result.sure, "and names him: " .. tostring(G.result and G.result.line))
local busy = 0 for _, c in ipairs(sent) do if c == "search" then busy = busy + 1 end end
ok(busy > 30, "searched again after every find and every 'still turning this room over'")


-- A theft case: the real lines from one --------------------------------------------------------
local T, tcur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-theft.log") do
  local name = l:match("^## (.+)$")
  if name then tcur = name; T[tcur] = {} elseif tcur then table.insert(T[tcur], l) end
end
G.newCase(); G.room = nil
feed(T.intro)
ok(G.case.kind == "theft" and G.inspectCmd == "inspect cradle" and G.inspectRoom == "Dr. Briefs' Study" and G.case.scene == "Dr. Briefs' Study",
  "theft intro: inspect cradle in the Study")
feed(T.guests); feed(T["notebook-start"])
local nq2 = 0 for _ in pairs(G.unquestioned) do nq2 = nq2 + 1 end
ok(nq2 == 12, "Statements 0 of 12 lists nobody: all twelve still to question (it questioned none before)")
ok(#G.partyRooms == 7 and G.partyRooms[5] == "Robot Workshop", "the party rooms a stash can be in")
G.room = "Front Steps"
local todo = G.todo()
ok(todo["Dr. Briefs' Study"] and todo["Dr. Briefs' Study"][1].kind ~= nil, "the Study is on the list (search and inspect cradle)")
local hasInspect = false
for _, task in ipairs(todo["Dr. Briefs' Study"]) do if task.kind == "inspect" then hasInspect = true end end
ok(hasInspect, "inspect goes to the Study, not the Front Steps")
feed(T.study)
ok(G.case.kind == "theft" and G.evidence[6], "the Study: a clue, and the reminder to inspect cradle")
feed(T.hangar)
ok(G.quiet[9], "party log: the radar was still in its cradle at nine, so not nine")
feed(T.kitchen)
ok(G.capsules.Kitchen, "a capsule in the Kitchen")
feed(T.portraits)
ok(G.code == "4852", "alphabetical plaque: Bulma, Dr. Briefs, Mrs. Briefs, Trunks = 4852")
feed(T.gravity); feed(T.attic)
ok(G.classify(G.evidence[4].text) == "hair" and select(2, G.classify(G.evidence[4].text)) == "not dark",
  "'a tuft of something that is not dark hair' is not dark")
ok(not G.secrets["a black calling card"] and next(G.secrets) == nil, "the Phantom's calling card is no secret")
feed(T["notebook-later"])
ok(G.capsules.Kitchen and G.capsules["Menagerie Yard"] and G.capsules.Conservatory, "notebook: capsules in the Kitchen, Menagerie Yard and Conservatory")
nq2 = 0 for _ in pairs(G.unquestioned) do nq2 = nq2 + 1 end
ok(nq2 == 12, "still nobody questioned: all twelve on the list")
feed(T["statements-empty"]); feed(T.accuse)
ok(G.akw.format == "accuse <suspect> stash <room> at <time>" and table.concat(G.akw.rooms, " ") == "grand dining family kitchen workshop menagerie conservatory",
  "accuse: stash format and the room words")
LOG = ""
local r = G.report()
ok(LOG:find("Nobody has been questioned yet", 1, true) and not r.sure and LOG:find("Stash:", 1, true), "without statements it says so, and never claims to be sure")

-- the stash, with statements: Pilaf slipped off at ten (Krillin was in the Grand Hall and didn't see him),
-- then went to the Kitchen; everyone else is seen by a witness
local function st(room, ...) return { room = room, with = { ... } } end
G.statements = {}
for t = 9, 12 do G.statements[t] = {} end
G.window = { [10] = true, [11] = true }
local others = { "Oolong", "Yajirobe", "Mai", "Tien", "Gohan", "Piccolo", "Videl" }
for t = 9, 12 do
  G.statements[t]["Android 18"] = st("Dining Room", table.unpack and table.unpack(others) or unpack(others))
  for _, o in ipairs(others) do G.statements[t][o] = st("Dining Room", "Android 18") end
end
G.statements[10]["Emperor Pilaf"] = st("Grand Hall", "Krillin")
G.statements[10].Krillin = st("Grand Hall")
G.statements[11]["Emperor Pilaf"] = st("Kitchen", "Yajirobe")
G.statements[12]["Emperor Pilaf"] = st("Grand Hall")
G.chart = {}
r = G.solve()
ok(r.suspect == "Emperor Pilaf" and r.time == 10 and r.stash == "Kitchen" and not r.stashGuess,
  "theft: Pilaf at ten, and the Kitchen is the capsule room he went to after")
ok(r.line == "accuse pilaf stash kitchen at ten", "the accusation: " .. tostring(r.line))
sent = {}; G.command("accuse")
ok(sent[1] == "accuse pilaf stash kitchen at ten", "gum accuse sends the stash accusation")

-- The same theft, questioned by hand: the cradle's time and the answers themselves
G.newCase(); G.room = nil
feed(T.intro); feed(T.guests); feed(T["notebook-start"])
feed(T.questioned)
ok(G.window[9] and G.window[10] and not G.window[11], "the cradle: taken between nine and ten")
ok(G.statements[9].Gohan.room == "Grand Hall" and G.statements[9].Gohan.with[1] == "Emperor Pilaf",
  "question gohan: at nine, Grand Hall with Emperor Pilaf")
ok(#G.statements[10].Gohan.with == 2 and G.statements[10].Gohan.with[2] == "Chi-Chi", "...at ten with Videl and Chi-Chi")
ok(G.statements[12]["Emperor Pilaf"].room == "Family Lounge" and #G.statements[12]["Emperor Pilaf"].with == 2,
  "question pilaf: at midnight, Family Lounge with Yajirobe and Krillin")
ok(G.questioned.Gohan and G.questioned["Emperor Pilaf"] and not G.unquestioned.Gohan, "both marked questioned")
feed(T["notebook-questioned"])
ok(G.quiet[9] and #G.crimeTimes() == 1 and G.crimeTimes()[1] == 10, "notebook: between nine and ten, still in the cradle at nine, so ten")
nq2 = 0 for _ in pairs(G.unquestioned) do nq2 = nq2 + 1 end
ok(nq2 == 10 and G.unquestioned.Videl and not G.unquestioned.Gohan, "the ten still to question")
ok(G.parseAnswer("In the Dining Room, with Launch, Mr. Satan and Mr. Popo. Keeping an eye.").with[3] == "Mr. Popo",
  "answers with Mr. names split right")
local alone = G.parseAnswer("In the Kitchen, alone. Honest.")
ok(alone.room == "Kitchen" and #alone.with == 0, "an answer with nobody else: no companions")

-- gum question: only the questioning
G.room = "Dr. Briefs' Study"; G.visited = {}
for r2 in pairs(G.EXITS) do G.visited[r2] = true end
G.where = { Oolong = "Dining Room", Videl = "Menagerie Yard" }
G.onlyQuestions = true
local q = G.todo()
G.onlyQuestions = nil
ok(q["Dining Room"] and q["Dining Room"][1].kind == "question" and q["Menagerie Yard"] and not q["Inner Hall"],
  "gum question: walks only to the guests, nothing else")
G.visited = { ["Dr. Briefs' Study"] = true }
G.onlyQuestions = true
q = G.todo()
G.onlyQuestions = nil
ok(q["Inner Hall"] and q["Inner Hall"][1].kind == "visit", "...and looks in rooms not seen yet for the guests it hasn't found")

-- The whole theft, as it really went: Piccolo is the one nobody saw at ten -----------------------
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests", "notebook-start" }) do feed(T[k]) end
feed({ "The seating chart, every place card signed at the feast:", "At nine: Yajirobe, Krillin.", "At ten: Yajirobe, Emperor Pilaf, Mai.",
       "At eleven: Oolong, Tien.", "At midnight: Piccolo, Videl, Android 18." })
feed({ "Garter's door log for ten, heads per room:", "  Grand Hall       0", "  Dining Room      3", "  Family Lounge    3",
       "  Kitchen          sensor broken", "  Study            sensor broken", "  Robot Workshop   0", "  Menagerie Yard   3", "  Conservatory     2" })
for _, k in ipairs({ "kitchen", "questioned", "notebook-questioned", "answers", "final-statements", "accuse" }) do feed(T[k]) end
local rank3, tag3, why3 = G.alibi("Piccolo", 10)
ok(tag3 == "LIED" and why3:find("Android 18", 1, true), "Piccolo at ten: Android 18 was in the Conservatory and didn't see him")
ok(select(2, G.alibi("Emperor Pilaf", 10)) == "seen", "Pilaf at ten: on the seating chart")
r = G.solve()
ok(r.suspect == "Piccolo" and r.time == 10 and r.stash == "Conservatory", "solve: Piccolo at ten, and he went on to the Conservatory")
ok(r.line == "accuse piccolo stash conservatory at ten", "the accusation: " .. tostring(r.line))
ok(r.analyze == 6, "the light footprints don't fit him: analyze 6 to see if they were planted")
ok(not r.sure, "with a clue against him it's a best guess, not solved")

-- Installed mid-case over an older version: the case is kept, the new fields are added
G.newCase()
feed(T.intro)
G.questioned, G.capsules, G.partyRooms, G.akw.rooms, G.case.kind = nil, nil, nil, nil, nil
dofile("packages/Gumshoe/src/Gumshoe.lua")
G = gum
ok(G.questioned and G.capsules and G.akw.rooms and G.case.kind == "murder" and #G.guests == 12,
  "reinstalled mid-case: the guests are kept and the new fields exist")
local okLine = pcall(G.line, 'Yajirobe tells you, \'Fine, here.\'') and pcall(G.line, 'At midnight: "In the Family Lounge, with Krillin. Napping."')
ok(okLine and G.questioned.Yajirobe, "and answers are read without an error")

-- gum solve re-reads the notebook first: an upgrade (or anything else) can't leave it with stale data
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests" }) do feed(T[k]) end
G.capsules = {}
local later = function(lines) tempTimer(0.1, function() feed(lines) end) end
respond = function(c)
  if c == "notebook" then return later(T["notebook-questioned"]) end
  local t = tonumber(c:match("^notebook (%d+)$") or "")
  if t then
    local block, which = { "========================================" }, 0
    for _, l in ipairs(T["final-statements"]) do
      if l:find("^STATEMENTS ABOUT") then which = which + 1 end
      if which == t - 8 then block[#block + 1] = l end
    end
    return later(block)
  end
  if c == "accuse" then return later(T.accuse) end
end
sent = {}; LOG = ""
G.command("solve")
wait(10)
ok(table.concat(sent, ",") == "notebook,notebook 9,notebook 10,notebook 11,notebook 12,accuse", "gum solve reads notebook, the four times and accuse: " .. table.concat(sent, ","))
ok(G.capsules.Conservatory and G.result and G.result.line == "accuse piccolo stash conservatory at ten",
  "...and solves from what it just read: " .. tostring(G.result and G.result.line))
respond = nil

-- The plate, as other cases word it, and a plate that's already used up ---------------------------
G.newCase(); G.room = nil
feed({ "Mrs. Briefs' stand-in checks her list: Yajirobe ate a slice of cake." })
ok(G.traits.Yajirobe.cake == "ate" and G.plated == "Yajirobe", "\"Yajirobe ate a slice of cake\" is read as a plate")
G.newCase()
feed({ "========================================", "THE GUESTS, AS ANYONE CAN SEE THEM", "========================================",
  "  Yajirobe       flaring heavy dark", "Cake: Yajirobe ate cake. Nobody else's plate is known." })
ok(G.traits.Yajirobe.cake == "ate" and G.plated == "Yajirobe", "...and so is the guest table's Cake line after a plate")
G.newCase()
feed({ "A stand-in of Mrs. Briefs tells you, 'One peek at my list per party, dear. I am a hostess, not a tattletale.'" })
ok(G.plated, "\"One peek at my list per party\": the plate is used up")

-- The Yamcha case just before the plate, with a Mrs. Briefs who won't answer: it must plate once, not loop
G.newCase(); G.room = "Kitchen"
for _, k in ipairs({ "intro", "notebook-start", "guests", "first-statements", "chart", "logs", "found", "inspect",
  "portraits", "confront", "final-statements", "notebook-end", "accuse" }) do feed(S[k]) end
G.analyses = 0
respond = function(c)
  local t = tonumber(c:match("^notebook (%d+)$") or "")
  if t then
    local block, which = {}, 0
    for _, l in ipairs(S["final-statements"]) do
      if l:find("^STATEMENTS ABOUT") then which = which + 1 end
      if which == t - 8 then block[#block + 1] = l end
    end
    return later(block)
  end
  if c == "notebook guests" then return later(S.guests) end
  if c == "accuse" then return later(S.accuse) end
  if c:find("^plate") then return later({ "A stand-in of Mrs. Briefs tells you, 'One peek at my list per party, dear. I am a hostess, not a tattletale.'" }) end
end
sent = {}; G.running = true; G.gen = G.gen + 1
G.finish()
wait(120)
local plates = 0 for _, c in ipairs(sent) do if c:find("^plate") then plates = plates + 1 end end
ok(plates == 1 and not G.running and G.result and G.result.line, ("plates once, then names it (%d plates, %d commands)"):format(plates, #sent))
respond = nil

-- The Phantom's calling cards ------------------------------------------------------------------
G.newCase(); G.room = "Attic"; G.cards = nil
feed({ " Calling cards:   2" })
ok(G.cards == 2, "casebook: two calling cards held")
local card
for _, l in ipairs(T.attic) do if l:find("calling card") then card = l end end
LOG = ""; feed({ card })
ok(G.card == "Attic" and not next(G.secrets) and LOG:find("that makes 3", 1, true), "a calling card in the Attic is spotted, not taken for a secret")
LOG = ""; feed(S.closed)
ok(G.cards == 3 and not G.card and LOG:find("summon the Phantom", 1, true), "solved in time: the card is kept, three of three")
G.newCase(); G.room = "Attic"; feed({ card }); feed({ "Case closed: gone cold." })
ok(G.cards == 3, "a cold case keeps no card")

-- Searching in the dark: get a light first ---------------------------------------------------
G.newCase(); G.room = "Kitchen"; G.flashlight = true
feed({ "It is pitch dark. You feel around and find nothing but furniture edges. take flashlight in the Hangar, or reset breaker in the Robot Charging Bay, then search again." })
local td = G.todo()
ok(G.gravityShut and not G.flashlight and td.Hangar and td.Hangar[1].kind == "flashlight" and next(td, next(td)) == nil,
  "pitch dark: the flashlight in the Hangar comes before anything else")
G.tries.flashlight = 2
G.unsearched["Gravity Chamber"] = true
td = G.todo()
ok(next(td) == nil, "no flashlight and the Gravity Chamber unsearched: no breaker, which would re-seal it")
G.searched["Gravity Chamber"] = true
td = G.todo()
ok(td["Robot Charging Bay"] and td["Robot Charging Bay"][1].kind == "breaker", "no flashlight after two tries: reset the breaker in the Robot Charging Bay")
sent = {}; G.room = "Attic"; feed({ card })
ok(sent[#sent] ~= "get card", "a calling card isn't an object: no get card (the game says so)")

-- Accomplices: one did it, one covered (the real lines from one) ---------------------------------
local A, acur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-accomplices.log") do
  local name = l:match("^## (.+)$")
  if name then acur = name; A[acur] = {} elseif acur then table.insert(A[acur], l) end
end
local function accomplices(skipCover)
  G.newCase(); G.room = nil
  for _, k in ipairs({ "intro", "guests", "answers", "confront", "notebook-end", "final-statements", "accuse", "analyze" }) do
    for _, l in ipairs(A[k]) do
      if not (skipCover and l:find("I covered for them")) then gum.line(l) end
    end
  end
  return G.solve()
end
r = accomplices()
ok(G.case.kind == "accomplices" and G.cover and G.cover.culprit == "Emperor Pilaf" and G.cover.coverer == "Mai",
  "Mai owns up: she covered for Emperor Pilaf")
ok(r.line == "accuse pilaf and mai with taser at ten", "accomplices: both names: " .. tostring(r.line))
r = accomplices(true)
ok(r.line == "accuse pilaf and mai with taser at ten",
  "...and without the confession, the two who first named each other in the Dining Room: " .. tostring(r.line))
sent = {}; G.command("accuse")
ok(sent[1] == "accuse pilaf and mai with taser at ten", "gum accuse sends the two-name accusation")

-- Hard cases: the analyzer is off -----------------------------------------------------------------
G.newCase()
feed({ "Difficulty: Hard. One more guest lies, the lab analyzer is off, and Garter's door log has a second broken sensor. Half again the pay, and a Good or Perfect solve earns a stronger boost." })
ok(G.case.difficulty == "Hard" and G.case.noAnalyzer, "Hard: read, and no lab runs")
G.analyses = 1
r = G.solve()
ok(not r.analyze and G.analyses == 0, "...so it never walks to the lab to analyze")

-- A Hard theft: the cradle "found empty by midnight", and a confession nobody in the room backs ----
local H2, hcur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-theft-hard.log") do
  local name = l:match("^## (.+)$")
  if name then hcur = name; H2[hcur] = {} elseif hcur then table.insert(H2[hcur], l) end
end
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests", "clues", "notebook-end", "logs", "final-statements", "accuse" }) do feed(H2[k]) end
ok(G.quiet[12] and #G.crimeTimes() == 1 and G.crimeTimes()[1] == 11, "found empty by midnight: taken at eleven")
local _, tagR = G.alibi("Master Roshi", 11)
local _, tagY = G.alibi("Yamcha", 11)
ok(tagR == "LIED" and tagY == "alone", "Roshi says he was with Yamcha and Pilaf, who name only each other, after a first story that was a lie: " .. tagR)
r = G.solve()
ok(r.line == "accuse roshi stash family at eleven", "Hard theft: " .. tostring(r.line))

-- Hard delayed sabotage: went off at midnight (nothing yet at eleven), timer two chimes -> rigged at ten.
-- Launch confessed to the Family Lounge at ten, but Mr. Popo was there and doesn't name her, and the log counts 3 of 4.
local S, scur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-sabotage-hard.log") do
  local name = l:match("^## (.+)$")
  if name then scur = name; S[scur] = {} elseif scur then table.insert(S[scur], l) end
end
G.newCase(); G.room = nil
feed(S.intro)
ok(G.case.kind == "sabotage", "Delayed sabotage read from the intro")
feed(S.guests); feed(S.chart); feed(S.remains)
r = G.solve()
ok(not r.sure, "no timer yet: not sure")
feed(S.timer)
ok(G.delay == 2, "timer: two chimes")
feed(S.partylog); feed(S.jacket)
ok(G.weapon == "Battle Jacket Mk.0", "the empty case names the weapon")
ok(#G.crimeTimes() == 1 and G.crimeTimes()[1] == 10, "went off at midnight, rigged at ten")
feed(S.logs); feed(S.evidence); feed(S["notebook-end"]); feed(S["final-statements"]); feed(S.plate); feed(S.accuse)
local rank, tagL = G.alibi("Launch", 10)
ok(tagL == "LIED", "Launch lied about ten")
ok(G.tookWeapon("Launch", 10, "Grand Hall"), "Launch was in the Grand Hall at nine")
r = G.solve()
ok(r.line == "accuse launch with jacket rigged at ten", "Hard sabotage: " .. tostring(r.line))
sent = {}; gum.command("accuse")
ok(sent[#sent] == "accuse launch with jacket rigged at ten", "gum accuse sends the rigged-at form: " .. tostring(sent[#sent]))
sent = {}
G.cards = 4
feed(S.card)
local got = false
for _, c in ipairs(sent) do if c == "get card" then got = true end end
ok(not got and G.card, "calling card noted, not picked up")

-- Lights Out: the breaker says ten or eleven, the party log says the alarm was up by eleven -> ten.
-- Four claim the Kitchen at ten but the log counts 3: Yamcha, Roshi and Videl name each other, nobody names Gohan.
local L, lcur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-lightsout.log") do
  local name = l:match("^## (.+)$")
  if name then lcur = name; L[lcur] = {} elseif lcur then table.insert(L[lcur], l) end
end
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests", "logs", "chart", "breaker", "weapon", "evidence" }) do feed(L[k]) end
feed(L.partylog)
ok(G.quiet[11], "party log: alarm already up by eleven rules out eleven")
for _, k in ipairs({ "notebook-end", "final-statements", "plate", "analyze", "accuse" }) do feed(L[k]) end
ok(#G.crimeTimes() == 1 and G.crimeTimes()[1] == 10, "lights out: ten")
local _, tg = G.alibi("Gohan", 10)
local _, tv = G.alibi("Videl", 10)
local _, ty = G.alibi("Yamcha", 10)
ok(tg == "LIED" and tv == "fits" and ty == "fits", "door log 3 of 4: only the one nobody names lied (" .. tg .. "/" .. tv .. "/" .. ty .. ")")
r = G.solve()
ok(r.line == "accuse gohan with lights at ten" and r.sure, "Lights Out: " .. tostring(r.line) .. " sure=" .. tostring(r.sure))

-- Hard murder: Piccolo first said the Dining Room at midnight (Krillin and Dende there, chart leaves him out),
-- then "confessed" to the Menagerie Yard with Yajirobe and Pilaf, who name only each other: lied twice.
local P, pcur = {}, nil
for l in io.lines("tests/fixtures/gumshoe-hard-firstlie.log") do
  local name = l:match("^## (.+)$")
  if name then pcur = name; P[pcur] = {} elseif pcur then table.insert(P[pcur], l) end
end
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests", "chart", "remains", "logs", "partylog", "weapon", "evidence", "plate",
                     "first-statements", "notebook-end", "final-statements", "accuse" }) do feed(P[k]) end
local _, tp, whyP = G.alibi("Piccolo", 12)
ok(tp == "LIED" and whyP:find("first said the Dining Room"), "unbacked confession after a proven first lie: " .. tostring(whyP))
local _, ts = G.alibi("Mr. Satan", 12)
ok(ts == "seen", "Satan's confession is backed by the chart: " .. ts)
r = G.solve()
ok(r.line == "accuse piccolo with gauntlet at midnight" and r.sure, "Hard first-lie: " .. tostring(r.line) .. " sure=" .. tostring(r.sure))

-- gum case: to Jaco and open a case ----------------------------------------------------
local function joined() return table.concat(sent, " | ") end
-- outside the house, with the capsule
G.newCase(); G.room = nil; sent = {}
respond = function(c)
  if c == "use mansion" then tempTimer(0.2, function() gum.line("Briefs Family Garden") end)
  elseif c == "w" then
    G._w = (G._w or 0) + 1
    if G._w == 6 then tempTimer(0.2, function() gum.line("Front Steps") end) end
  end
end
G._w = 0
gum.command("case")
wait(10)
ok(joined() == "look | use mansion | w | w | w | w | w | w | say case hard", "capsule, 6 west, say case hard: " .. joined())
-- no capsule: instant to Bulma, then pursue Jaco
sent = {}; G.room = nil
respond = function(c)
  if c == "use mansion" then tempTimer(0.2, function() gum.line("You don't have that.") end)
  elseif c == "focus 'instant' bulma" then tempTimer(0.5, function() feed({ "You touch two fingers to your forehead and disappear suddenly.", "Bulma's Workshop", "Bulma frowns at a schematic, a screwdriver behind one ear." }) end)
  elseif c == "pursue jaco" then tempTimer(3, function() feed({ "You begin tracking Jaco the Galactic Patrolman's ki...", "Front Steps", "You have successfully tracked down Jaco the Galactic Patrolman!" }) end)
  end
end
gum.command("case", "normal")
wait(10)
ok(joined() == "look | use mansion | focus 'instant' bulma | pursue jaco | say case normal", "no capsule: instant to Bulma, pursue Jaco: " .. joined())
-- the capsule keyword hits a scouter, and the instant fails twice before it lands
sent = {}; G.room = nil
local fails = 0
respond = function(c)
  if c == "use mansion" then tempTimer(0.2, function() gum.line("You can only use a scouter when wearing it.") end)
  elseif c == "focus 'instant' bulma" then
    fails = fails + 1
    if fails <= 2 then tempTimer(0.3, function() feed({ "Okay.", "You failed." }) end)
    else tempTimer(0.5, function() feed({ "Okay.", "You touch two fingers to your forehead and disappear suddenly.", "Bulma's Workshop" }) end) end
  elseif c == "pursue jaco" then tempTimer(3, function() feed({ "Front Steps" }) end)
  end
end
gum.command("case")
wait(15)
ok(joined() == "look | use mansion | focus 'instant' bulma | focus 'instant' bulma | focus 'instant' bulma | pursue jaco | say case hard", "instant retried after failing: " .. joined())
-- never lands: pursue Jaco from here
sent = {}; G.room = nil
respond = function(c)
  if c == "use mansion" then tempTimer(0.2, function() gum.line("You can only use a scouter when wearing it.") end)
  elseif c == "focus 'instant' bulma" then tempTimer(0.3, function() feed({ "Okay.", "You failed." }) end)
  elseif c == "pursue jaco" then tempTimer(3, function() feed({ "Front Steps" }) end)
  end
end
gum.command("case")
wait(20)
ok(joined() == "look | use mansion | focus 'instant' bulma | focus 'instant' bulma | focus 'instant' bulma | pursue jaco | say case hard", "instant keeps failing: pursue from here: " .. joined())
-- already in Bulma's Workshop
sent = {}; G.room = nil
respond = function(c)
  if c == "use mansion" then tempTimer(0.2, function() gum.line("You can only use a scouter when wearing it.") end)
  elseif c == "focus 'instant' bulma" then tempTimer(0.3, function() feed({ "Okay.", "But you are already in the same place as them." }) end)
  elseif c == "pursue jaco" then tempTimer(3, function() feed({ "Front Steps" }) end)
  end
end
gum.command("case")
wait(15)
ok(joined() == "look | use mansion | focus 'instant' bulma | pursue jaco | say case hard", "already with Bulma: pursue Jaco: " .. joined())
-- already in the house: walk out to the Front Steps
sent = {}; G.room = "Grand Hall"
respond = function(c)
  if c == "look" then tempTimer(0.2, function() gum.line("Grand Hall") end)
  elseif c == "s" then tempTimer(0.2, function() gum.line(G.room == "Grand Hall" and "Entrance Hall" or "Front Steps") end) end
end
gum.command("case")
wait(10)
ok(joined() == "look | s | s | say case hard", "inside the house: walk out: " .. joined())
respond = nil
-- the case is over and the robots walk you out to the Front Steps mid-walk: still arrived
sent = {}; G.room = "Kitchen"
respond = function(c)
  if c == "look" then tempTimer(0.2, function() gum.line("Kitchen") end)
  elseif c == "s" then tempTimer(0.2, function()
    gum.line("A pair of house robots take you by the elbows and walk you out to the Front Steps."); gum.line("Front Steps") end) end
end
gum.command("case")
wait(10)
ok(joined() == "look | s | say case hard", "robots walk you out: say case anyway: " .. joined())
respond = nil

-- after a case: one step through any exit (no known way from here), the robots walk you out
sent = {}; G.room = "East Corridor"; local savedPath = G.path
G.path = function() return nil end
respond = function(c)
  if c == "look" then tempTimer(0.2, function() gum.line("East Corridor") end)
  elseif c ~= "say case hard" then tempTimer(0.2, function()
    gum.line("A pair of house robots take you by the elbows and walk you out to the Front Steps."); gum.line("Front Steps") end) end
end
gum.command("case")
wait(10)
G.path = savedPath
ok(#sent == 3 and sent[1] == "look" and sent[3] == "say case hard" and G.room == "Front Steps", "no way known: any exit, out to Jaco: " .. joined())
respond = nil

-- toJaco with a callback (repeat waits there): gets there, says no case
sent = {}; G.room = "Kitchen"; local parked = false
respond = function(c)
  if c == "look" then tempTimer(0.2, function() gum.line("Kitchen") end)
  elseif c == "s" then tempTimer(0.2, function() gum.line("Front Steps") end) end
end
G.toJaco(nil, function() parked = true end)
wait(10)
ok(parked and not G.running and joined() == "look | s", "toJaco(nil, arrived): there, no case said: " .. joined())
respond = nil

-- gum auto: after say case, the end of Jaco's briefing starts the run ---------------------
G.auto = true
G.newCase(); G.room = nil; sent = {}
respond = function(c)
  if c == "look" then tempTimer(0.2, function() gum.line("Front Steps") end) end
end
G.toJaco()
wait(5)
ok(sent[#sent] == "say case hard", "auto: said case")
sent = {}
feed({ "The case: Bulma's stand-in lies smashed in the Conservatory.",
       "Lost? notebook brief shows this again and notebook commands lists every command. say abandon to Jaco" })
wait(2)
ok(sent[1] == "look" and G.running and G.autoChain, "auto: Jaco's briefing over, the run starts: " .. joined())
G.stop(); respond = nil
ok(not G.autoChain, "gum stop drops the auto accusation")
-- the run ends sure: accuse, and again when Jaco asks to confirm
G.newCase(); G.room = nil
for _, k in ipairs({ "intro", "guests", "chart", "remains", "logs", "partylog", "weapon", "evidence", "plate",
                     "first-statements", "notebook-end", "final-statements", "accuse" }) do feed(P[k]) end
sent = {}; G.autoChain = true
G.done(G.solve())
ok(joined() == "accuse piccolo with gauntlet at midnight", "auto: accuses when sure: " .. joined())
feed({ "Jaco's voice crackles over your tablet, 'You name Piccolo, with the Gauntlet, at midnight. Certain? Type accuse yes and I make the arrest.'" })
ok(joined() == "accuse piccolo with gauntlet at midnight | accuse piccolo with gauntlet at midnight", "auto: confirms with the same accusation: " .. joined())
-- not sure: says so instead of accusing
G.newCase(); G.room = nil; sent = {}; G.autoChain = true; LOG = ""
G.done(G.solve())
ok(#sent == 0 and LOG:find("Not sure enough", 1, true), "auto: a guess is never sent")
-- off: gum case only says case
G.command("auto", "off")
ok(G.auto == false, "gum auto off")
G.run(); ok(G.autoChain == false, "off: gum run doesn't arm the accusation"); G.stop()
G.command("auto", "on")

-- gum cd: Jaco's next case, 20 minutes after the culprit dies ------------------------------
G.clock = function() return now end
G.nextCase = nil
LOG = ""; G.cooldown()
ok(LOG:find("No finished case on record", 1, true), "gum cd: nothing known yet")
G.newCase(); G.guests = { "Gohan", "Piccolo" }
feed({ "Case closed: Perfect, no wrong accusations." })
LOG = ""; G.command("cd")
ok(LOG:find("Next case in 20:00", 1, true), "case closed: 20 minutes to go: " .. LOG)
wait(5 * 60)
feed({ "Krillin is dead!  R.I.P." })
LOG = ""; G.command("cooldown")
ok(LOG:find("Next case in 15:00", 1, true), "someone who isn't a guest dying changes nothing")
feed({ "Piccolo is dead!  R.I.P." })
LOG = ""; G.command("cd")
ok(LOG:find("Next case in 20:00", 1, true), "the culprit dies: the 20 minutes start again from there")
LOG = ""; wait(20 * 60)
ok(LOG:find("Jaco has a new case for you", 1, true), "and it tells you when Jaco has one")
LOG = ""; G.command("cd")
ok(LOG:find("Jaco has a new case for you", 1, true), "gum cd says so too")
wait(30 * 60); G.nextCase = now + 60
feed({ "Piccolo is dead!  R.I.P." })
ok(G.nextCase == now + 60, "a guest dying long after the case doesn't restart it")

print("gum: ALL PASSED")
