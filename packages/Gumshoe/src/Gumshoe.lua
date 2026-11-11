-- Gumshoe: Jaco's party mysteries at the Briefs mansion (help mansion). Type `gum help`.
--
-- Reads everything the case prints (notebook, statements, Garter's door log, the seating chart,
-- evidence, secrets, the remains), walks the house, and works out who did it. `gum run` does the
-- legwork: search every room until it's done, question every guest, inspect the remains, read the
-- door log, open the sealed rooms, confront the secrets, then re-read the statements and solve.
gum = gum or {}
local G = gum

-- ---------------------------------------------------------------- settings
G.searchDelay = G.searchDelay or 1.5   -- seconds between searches in the same room
G.busyDelay   = G.busyDelay or 2       -- after "You are still turning this room over."
G.stepTimeout = G.stepTimeout or 6     -- seconds to wait for a room / an answer
G.FEAST_ROOM  = "Dining Room"          -- the seating chart is who sat in here

local TIMES = { nine = 9, ten = 10, eleven = 11, midnight = 12, twelve = 12,
                ["9"] = 9, ["10"] = 10, ["11"] = 11, ["12"] = 12 }
local TIME_WORD = { [9] = "nine", [10] = "ten", [11] = "eleven", [12] = "midnight" }
G.TIMES, G.TIME_WORD = TIMES, TIME_WORD

-- Oldest to youngest, for the lab keypad's age plaques
G.AGE = { "Dr. Briefs", "Mrs. Briefs", "Bulma", "Trunks" }

-- ---------------------------------------------------------------- the house
-- Every room and its exits. lock = which sealed room the exit leads into.
G.EXITS = {}
local REV = { n = "s", s = "n", e = "w", w = "e", u = "d", d = "u" }
local function link(a, dir, b, lock)
  G.EXITS[a] = G.EXITS[a] or {}; G.EXITS[b] = G.EXITS[b] or {}
  G.EXITS[a][#G.EXITS[a] + 1] = { dir = dir, to = b, lock = lock }
  G.EXITS[b][#G.EXITS[b] + 1] = { dir = REV[dir], to = a }
end
link("Front Steps", "n", "Entrance Hall")
link("Entrance Hall", "e", "Sun Porch")
link("Entrance Hall", "w", "Cloakroom")
link("Entrance Hall", "n", "Grand Hall")
link("Cloakroom", "n", "Dining Room")
link("Sun Porch", "n", "Family Lounge")
link("Dining Room", "e", "Grand Hall")
link("Dining Room", "n", "Kitchen")
link("Dining Room", "w", "Service Yard")
link("Service Yard", "w", "Menagerie Yard")
link("Menagerie Yard", "n", "Dinosaur Paddock")
link("Menagerie Yard", "s", "Pond and Aviary")
link("Grand Hall", "e", "Family Lounge")
link("Grand Hall", "n", "Inner Hall")
link("Kitchen", "e", "Inner Hall")
link("Family Lounge", "n", "Dr. Briefs' Study")
link("Family Lounge", "e", "Covered Walkway")
link("Covered Walkway", "e", "Robot Workshop")
link("Robot Workshop", "n", "Hangar")
link("Robot Workshop", "s", "Gravity Chamber", "gravity")
link("Inner Hall", "e", "Dr. Briefs' Study")
link("Inner Hall", "n", "Portrait Gallery")
link("Portrait Gallery", "n", "Garden Hall")
link("Garden Hall", "n", "Lab Vestibule")
link("Lab Vestibule", "d", "Underground Lab", "lab")
link("Garden Hall", "w", "West Corridor")
link("West Corridor", "w", "Robot Charging Bay")
link("Robot Charging Bay", "u", "Upper Landing West")
link("Upper Landing West", "w", "Master Bedroom")
link("Upper Landing West", "u", "Attic")
link("Garden Hall", "e", "East Corridor")
link("East Corridor", "e", "Conservatory")
link("Conservatory", "u", "Upper Landing East")
link("Upper Landing East", "n", "Infirmary")
link("Upper Landing East", "e", "Bulma's Suite", "suite")

-- The sealed rooms, by lock
G.SEALED = { lab = "Underground Lab", gravity = "Gravity Chamber", suite = "Bulma's Suite" }

-- How the notebook names a room -> the room's title
G.ALIAS = { ["Study"] = "Dr. Briefs' Study", ["Lab"] = "Underground Lab", ["the lab"] = "Underground Lab" }
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function roomName(s) s = trim(s); return G.ALIAS[s] or s end
G.roomName = roomName

-- ---------------------------------------------------------------- state
function G.newCase()
  G.case = { title = nil, scene = nil, difficulty = nil, minutes = nil, wrong = 0, kind = "murder" }
  G.inspectCmd, G.inspectRoom = nil, nil   -- "inspect remains" at the scene, "inspect cradle" in the Study...
  G.capsules = {}          -- theft: rooms with a Hoi Poi capsule (one holds the loot)
  G.partyRooms = {}        -- theft: the rooms a stash can be in
  G.questioned = {}        -- guests this script questioned
  G.guests = {}            -- every guest's name, in the intro's order
  G.witnesses = {}         -- name -> true: never the culprit, never lie
  G.traits = {}            -- name -> { ki, tread, hair, cake }
  G.statements = {}        -- [time][name] = { room, with = {...}, first = room they first claimed }
  G.window = nil           -- [time] = true: when the stand-in stopped
  G.quiet = {}             -- [time] = true: the log says all was quiet
  G.time = nil             -- resolved time
  G.weapon = nil           -- resolved weapon name
  G.weaponCands = {}       -- { { name, room }, ... } from the damage
  G.weaponsAll = {}        -- every weapon on the list
  G.chart = {}             -- [time][name] = true, seats at the feast
  G.log = {}               -- [time][room] = heads | "broken"
  G.evidence = {}          -- [n] = { text, status }
  G.evFound, G.evTotal = 0, nil
  G.analyses = nil         -- analyzes left
  G.secrets = {}           -- [guest] = { what, room, confronted, phrase }
  G.phrase = nil           -- Bulma's Suite voice lock
  G.unsearched = {}        -- rooms the notebook still lists
  G.searched = {}          -- rooms this script finished searching
  G.unquestioned = {}      -- [guest] = true
  G.where = {}             -- [guest] = room they were last seen in
  G.visited = {}           -- rooms walked into this case
  G.open = { lab = nil, gravity = nil, suite = nil }   -- true open / false sealed / nil unknown
  G.gravityShut, G.flashlight = false, false
  G.portraits, G.plaque, G.code = {}, nil, nil
  G.inspected, G.logsRead, G.plated, G.analyzed = false, {}, nil, nil
  G.akw = { suspects = {}, weapons = {}, rooms = {}, format = nil }  -- keywords from `accuse`
  G.tries = {}
end
if not G.case then G.newCase() end
G.room = G.room
G.gen = G.gen or 0

local function info(color, msg) cecho("\n<" .. color .. ">[gum] " .. msg .. "\n") end
G.info = info

-- "A, B and C." -> { A, B, C }; rooms = true splits on commas only ("Pond and Aviary")
local function split(list, rooms)
  local out = {}
  list = list:gsub("%.$", "")
  if not rooms then list = list:gsub(",? and ", ", ") end
  for part in list:gmatch("[^,]+") do
    local name = trim(part)
    if name ~= "" then out[#out + 1] = name end
  end
  return out
end
G.split = split

local function setOf(list) local s = {} for _, x in ipairs(list) do s[x] = true end return s end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function has(list, x) for _, y in ipairs(list) do if y == x then return true end end end

local function addGuest(name)
  if not has(G.guests, name) then G.guests[#G.guests + 1] = name end
end

-- ---------------------------------------------------------------- waiting for the game
-- One wait at a time: a list of { pattern, key } (a pattern "@name" waits for G.emit("name")).
local W
local function clearWait()
  if W and W.timer then killTimer(W.timer) end
  W = nil
end
local function expect(pats, timeout, cb)
  clearWait()
  local w = { pats = pats, cb = cb }
  W = w
  w.timer = tempTimer(timeout, function()
    if W == w then W = nil; cb("timeout") end
  end)
end
local function check(s, signal)
  if not W then return end
  for _, p in ipairs(W.pats) do
    local hit
    if signal then hit = p[1] == "@" .. s else hit = p[1]:sub(1, 1) ~= "@" and s:find(p[1]) end
    if hit then
      local w = W
      clearWait()
      w.cb(p[2])
      return
    end
  end
end
function G.emit(name) check(name, true) end

-- Run fn after a delay, unless the run was stopped meanwhile
local function later(delay, fn)
  local gen = G.gen
  tempTimer(delay, function() if G.running and G.gen == gen then fn() end end)
end

local function cmd(c, pats, timeout, cb)
  send(c, false)
  expect(pats, timeout or G.stepTimeout, cb)
end

local function seq(steps, done)
  local i = 0
  local function nxt()
    if not G.running then return end
    i = i + 1
    if i > #steps then return done() end
    steps[i](nxt)
  end
  nxt()
end

-- ---------------------------------------------------------------- keywords
local SPECIAL = { ["Android 18"] = "android", ["Lights Out Capsule"] = "lights", ["Battle Jacket Mk.0"] = "jacket" }
-- The word to type for a guest or weapon: from `accuse`'s list when we have it.
function G.keyword(name, list)
  local low = name:lower()
  for _, k in ipairs(list or {}) do
    if low:find(k, 1, true) then return k end
  end
  if SPECIAL[name] then return SPECIAL[name] end
  if list == G.akw.weapons then return low:match("^(%w+)") end
  if list == G.akw.rooms then return ({ ["robot workshop"] = "workshop" })[low] or low:match("^(%w+)") end
  return low:match("(%w+)$")
end
local function guestKw(name) return G.keyword(name, G.akw.suspects) end

-- ---------------------------------------------------------------- walking
function G.path(from, to)
  if not (from and G.EXITS[from] and G.EXITS[to]) then return nil end
  if from == to then return {} end
  local prev, queue, head = { [from] = false }, { from }, 1
  while queue[head] do
    local r = queue[head]; head = head + 1
    for _, e in ipairs(G.EXITS[r]) do
      if prev[e.to] == nil and (not e.lock or G.open[e.lock] == true) then
        prev[e.to] = { r, e.dir }
        if e.to == to then
          local p, cur = {}, to
          while prev[cur] do table.insert(p, 1, { dir = prev[cur][2], room = cur }); cur = prev[cur][1] end
          return p
        end
        queue[#queue + 1] = e.to
      end
    end
  end
end

local BLOCKED = { { "^Alas, you cannot go that way", "blocked" }, { "^Three hundred G pin you", "blocked" },
                  { "^The voice lock blinks red", "blocked" } }

function G.walk(to, cb)
  if G.room == to then return cb(true) end
  local p = G.path(G.room, to)
  if not p then
    info("red", "No open way from " .. tostring(G.room) .. " to " .. to)
    return cb(false)
  end
  local i = 0
  local function step()
    i = i + 1
    if i > #p then return cb(true) end
    local pats = { { "@arrived", "ok" } }
    for _, b in ipairs(BLOCKED) do pats[#pats + 1] = b end
    cmd(p[i].dir, pats, G.stepTimeout, function(k)
      if k == "ok" and G.room == p[i].room then return step() end
      info("red", "Lost the way to " .. to .. " (" .. (k == "ok" and ("ended up in " .. tostring(G.room)) or k) .. ")")
      cb(false)
    end)
  end
  step()
end

-- ---------------------------------------------------------------- reading the game
local B = {}   -- the block being read: { kind, eq = ==== lines seen, ... }

local function parseStatement(t, text)
  -- "Launch, with Yamcha and Krillin (first said the Grand Hall)."
  local name, rest = text:match("^(.-), (.*)%.$")
  if not name then return end
  local first = rest:match("%(first said the (.-)%)")
  rest = rest:gsub("%s*%(.-%)", "")
  local with = {}
  local list = rest:match("^with (.+)$")
  if list then with = split(list) end
  G.statements[t][name] = { room = B.room, with = with, first = first and roomName(first) or nil }
  addGuest(name)
end

-- Time words in a text, in the order they appear: "between ten and midnight" -> { 10, 12 }
local function timesIn(text)
  local out = {}
  for w in text:lower():gmatch("%a+") do
    if TIMES[w] and w ~= "twelve" then out[#out + 1] = TIMES[w] end
  end
  return out
end
G.timesIn = timesIn

local function setWindow(text)
  local ts = timesIn(text)
  if #ts >= 2 and text:find("between") then
    G.window = {}
    for t = math.min(ts[1], ts[2]), math.max(ts[1], ts[2]) do G.window[t] = true end
  elseif #ts == 1 then
    G.window = { [ts[1]] = true }
  end
end

-- "inspect cradle in the Study for when..." / "inspect remains at the scene for..."
local function readInspect(text)
  local c, room = text:match("(inspect %a+) in the (.-) for")
  if not c then c, room = text:match("(inspect %a+) in the (.-)%.") end
  if c then G.inspectCmd, G.inspectRoom = c, roomName(room); return true end
  c = text:match("(inspect %a+) at the scene")
  if c then G.inspectCmd = c; return true end
end
G.readInspect = readInspect

local function parseLead(done, n, text)
  B.section = n
  if n == 1 then
    if done then
      G.inspected = true
      setWindow((text:match("^When: ([^;]*)") or ""))
      for q in text:gmatch("quiet at (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
    else
      readInspect(text)
    end
  elseif n == 2 then
    local w, r = text:match("^Weapon: the (.-), kept in the (.-)%.")
    if done and w then G.weapon = w; G.weaponCands = { { name = w, room = roomName(r) } } end
    if text:find("^Stash:") then G.case.kind = "theft" end
    local caps = text:match("capsules found, in (.-)%. ")
    if caps then
      caps = caps:gsub("the ", ""):gsub("Pond and Aviary", "Pond&Aviary")
      for _, r2 in ipairs(split(caps)) do G.capsules[roomName((r2:gsub("&", " and ")))] = true end
    end
  elseif n == 3 then
    local f, t = text:match("(%d+) of (%d+) found")
    if f then G.evFound, G.evTotal = tonumber(f), tonumber(t) end
    local left = text:match("%((%d+) left%)")
    G.analyses = left and tonumber(left) or 0
    G.unsearched = {}
  elseif n == 4 then
    -- "Statements: 0 of 12." lists nobody: everyone we haven't questioned is still to do
    G.unquestioned = {}
    local a, b = text:match("(%d+) of (%d+)")
    if a and tonumber(a) < tonumber(b) then
      for _, g in ipairs(G.guests) do if not G.questioned[g] then G.unquestioned[g] = true end end
    end
  elseif n == 5 then
    for part in (text:match("^Secrets: (.*)$") or ""):gmatch("[^;]+") do
      local who, state = part:match("^%s*(.-) %((%a[%a ]*)%)")
      if who then
        G.secrets[who] = G.secrets[who] or {}
        G.secrets[who].confronted = state == "confronted"
        if part:find("a phrase on the back") then G.secrets[who].hasPhrase = true end
      end
    end
  elseif n == 6 then
    local lab = text:match("the lab (%a+)")
    if lab then G.open.lab = lab == "open" end
    local grav = text:match("the Gravity Chamber (%S+)")
    if grav then G.open.gravity = grav:gsub("[;,.]$", "") == "open" end
    local suite = text:match("Bulma's Suite (%a+)")
    if suite then G.open.suite = suite == "open" end
  elseif n == 7 then
    local f = text:match("(%d+) of %d+ findings")
    if f then G.findings = tonumber(f) end
  end
end

local function notebookLine(l)
  local mins = l:match("^Status: %u+, (%d+) minutes left")
  if mins then G.case.minutes = tonumber(mins); return end
  local scene = l:match("^Case: .*, (.-)$")
  if scene then G.case.scene = roomName(scene); G.case.title = l:match("^Case: (.*)$"); return end
  local diff = l:match("^Difficulty: (%a+)")
  if diff then G.case.difficulty = diff; return end
  local wrong = l:match("^Wrong accusations: (%d+)")
  if wrong then G.case.wrong = tonumber(wrong); return end
  local mark, n, text = l:match("^ %[([ x])%] (%d+)%. (.*)$")
  if mark then return parseLead(mark == "x", tonumber(n), text) end
  local weapons = l:match("^Weapons: (.+)$")
  if weapons then G.weaponsAll = split(weapons); return end
  local kind = l:match("^Kind: (%a+)")
  if kind then G.case.kind = kind:lower(); return end
  local rooms = l:match("^Rooms: (.+)$")
  if rooms then
    G.partyRooms = {}
    for _, r in ipairs(split(rooms, true)) do G.partyRooms[#G.partyRooms + 1] = roomName(r) end
    return
  end
  if B.section == 3 then
    local en, status, etext = l:match("^%s+#(%d+) %[(%a+)%] (.+)$")
    if en then
      G.evidence[tonumber(en)] = { text = etext, status = status:lower() }
      return
    end
    if l:find("Not searched yet") then B.list = "rooms"; return end
    if l:find("Searched: every open room") then B.list = nil; return end
    if B.list == "rooms" then
      for _, r in ipairs(split((trim(l):gsub(",$", "")), true)) do G.unsearched[roomName(r)] = true end
      if l:find("%.%s*$") then B.list = nil end
    end
  elseif B.section == 4 then
    local list = l:match("Not questioned yet: (.+)$")
    if list then B.list = "guests"; G.unquestioned = {} end
    if B.list == "guests" then
      for _, g in ipairs(split(trim(list or l):gsub(",$", ""))) do G.unquestioned[g] = true; addGuest(g) end
      if l:find("%.%s*$") then B.list = nil end
    end
  end
end

local function guestsLine(l)
  local name, ki, tread, hair = l:match("^  (%S.-)%s%s+(%a+)%s+(%a+)%s+(.-)%s*$")
  if name and (ki == "flaring" or ki == "quiet") then
    local t = G.traits[name] or {}
    t.ki, t.tread, t.hair = ki, tread, hair
    G.traits[name] = t
    addGuest(name)
    return
  end
  local wit = l:match("^Witnesses: (.-)%. Never")
  if wit then
    G.witnesses = setOf(split(wit))
    for w in pairs(G.witnesses) do addGuest(w) end
  end
end

-- Portrait order -> keypad code
function G.codeFromPortraits(portraits, plaque)
  if #portraits == 0 or not plaque then return nil end
  local p = plaque:lower()
  local order = {}
  if p:find("right to left") then
    for i = #portraits, 1, -1 do order[#order + 1] = portraits[i] end
  elseif p:find("left to right") then
    order = portraits
  elseif p:find("alphabetical") then
    for _, x in ipairs(portraits) do order[#order + 1] = x end
    local rev = p:find("reverse") or p:find("z to a")
    table.sort(order, function(a, b) if rev then return a.name > b.name end return a.name < b.name end)
  elseif p:find("old") or p:find("young") then
    local rank = {}
    for i, n in ipairs(G.AGE) do rank[n] = i end
    for _, x in ipairs(portraits) do
      if not rank[x.name] then return nil end
      order[#order + 1] = x
    end
    local youngFirst = p:find("young") and (not p:find("old") or p:find("young") < p:find("old"))
    table.sort(order, function(a, b)
      if youngFirst then return rank[a.name] > rank[b.name] end
      return rank[a.name] < rank[b.name]
    end)
  else
    return nil
  end
  local code = ""
  for _, x in ipairs(order) do code = code .. x.digit end
  return code
end

local function arrived()
  B.listing = nil
  G.emit("arrived")
end

function G.line(l)
  l = l:gsub("%s+$", "")

  -- the room we're in, and who stands there
  if G.EXITS[l] then
    G.room = l
    G.visited[l] = true
    B.listing = { room = l }
    for g, r in pairs(G.where) do if r == l then G.where[g] = nil end end
    tempTimer(0.4, arrived)
    check(l)
    return
  end
  if B.listing then
    for _, g in ipairs(G.guests) do
      if l:sub(1, #g + 1) == g .. " " and not l:find("^" .. g:gsub("%.", "%%.") .. " tells you") then
        G.where[g] = B.listing.room
      end
    end
  end

  -- a new case
  if l:find("^Tonight is the .- party%.") then G.newCase(); G.case.season = l:match("^Tonight is the (.-) party") end
  local diff = l:match("^Difficulty: (%a+)%.$")
  if diff then G.case.difficulty = diff end
  local caseText = l:match("^The case: (.+)$")
  if caseText then
    G.case.title = caseText
    local scene = caseText:match("in the (.-)%.")
    G.case.scene = scene and roomName(scene) or nil
  end
  if l:find("^Theft: ") then G.case.kind = "theft" end
  local start = l:match("^%s*%d+%. (inspect %a+ .*)$")
  if start then readInspect(start) end
  if l:find("^Nobody was hurt tonight") and readInspect(l) then G.case.kind = "theft"; G.inspected = false end
  local party = l:match("people were at the party: (.+)%.$")
  if party then for _, g in ipairs(split(party)) do addGuest(g); G.unquestioned[g] = true end end

  -- blocks with ==== borders
  if l:find("^GALACTIC PATROL, PARTY INCIDENT REPORT") then
    B.kind, B.eq, B.section, B.list = "notebook", 0, nil, nil
    G.unsearched, G.unquestioned = {}, {}
  elseif l:find("^STATEMENTS ABOUT ") then
    local t = TIMES[(l:match("^STATEMENTS ABOUT (%u+)") or ""):lower()]
    B.kind, B.eq, B.time = "statements", 0, t
    if t then G.statements[t] = {} end
    if l:find("in the window") and t then G.window = G.window or {}; G.window[t] = true end
  elseif l:find("^THE GUESTS, AS ANYONE CAN SEE THEM") then
    B.kind, B.eq = "guests", 0
  elseif l:find("^=====") then
    if B.kind then
      B.eq = B.eq + 1
      if B.eq >= 2 then
        local k = B.kind
        B.kind = nil
        G.emit(k)
      end
    end
  elseif B.kind == "notebook" then
    notebookLine(l)
  elseif B.kind == "statements" and B.time then
    local room = l:match("^(%a.-), %d+ says? so:$")
    if room then B.room = roomName(room)
    elseif l:find("^   %S") then parseStatement(B.time, trim(l)) end
  elseif B.kind == "guests" then
    guestsLine(l)
  end

  -- Garter's door log
  local logTime = l:match("^Garter's door log for (%a+), heads per room:")
  if logTime then
    B.log = TIMES[logTime]
    G.log[B.log] = {}
    G.logsRead[B.log] = true
    tempTimer(0.5, function() B.log = nil; G.emit("log") end)
  elseif B.log then
    local r, n = l:match("^  (%S.-)%s%s+(%d+)$")
    if r then G.log[B.log][roomName(r)] = tonumber(n) end
    r = l:match("^  (%S.-)%s%s+sensor broken$")
    if r then G.log[B.log][roomName(r)] = "broken" end
  end

  -- the seating chart
  if l:find("^The seating chart") then
    B.chart = true
  elseif B.chart then
    local t, names = l:match("^At (%a+): ([^\"]+)%.$")
    if t and TIMES[t] then G.chart[TIMES[t]] = setOf(split(names)) else B.chart = nil end
  end

  -- searching
  local etext, en = l:match("^You find (.-)%. %(evidence #(%d+)%)")
  if en then
    G.evidence[tonumber(en)] = G.evidence[tonumber(en)] or { text = etext, status = "unverified" }
    G.evFound = math.max(G.evFound or 0, count(G.evidence))
  end
  local what, owner, room = l:match("^Tucked out of sight: (.-)%. That belongs to (.-), in the (.-): confront")
  if what then
    G.secrets[owner] = G.secrets[owner] or {}
    G.secrets[owner].what, G.secrets[owner].room = what, roomName(room)
    B.secret = owner
  else
    local phrase = l:match('^Scribbled on the back: "(.-)"')
    if phrase then
      G.phrase = phrase
      if B.secret then G.secrets[B.secret].phrase = phrase; G.secrets[B.secret].hasPhrase = true end
    end
    if not l:find("^%[") then B.secret = nil end
  end
  if l:find("^Tucked out of sight: a plain Hoi Poi capsule") and G.room then G.capsules[G.room] = true end
  local stillAt = l:match("party log: at (%a+), ")
  if stillAt and TIMES[stillAt] and l:find("still") then G.quiet[TIMES[stillAt]] = true end
  if l:find("cradle") and not l:find("still in its cradle") and not l:find("inspect cradle") and #timesIn(l) > 0 then
    setWindow(l)
    G.inspected = true
  end
  if l:find("This room is done for now") or l:find("^Nothing is ever hidden in") then
    if G.room then G.searched[G.room] = true; G.unsearched[G.room] = nil end
  end

  -- the remains
  local w1, r1, w2, r2 = l:match("Either the (.-) from the (.-), or the (.-) from the (.-)%.")
  if w1 then
    G.weaponCands = { { name = w1, room = roomName(r1) }, { name = w2, room = roomName(r2) } }
    G.inspected = true
  end
  local a, b = l:match("stopped between (%a+) and (%a+)%.")
  if a and TIMES[a] and TIMES[b] then
    G.window = {}
    for t = TIMES[a], TIMES[b] do G.window[t] = true end
    G.inspected = true
  end
  local at = l:match("heart capsule stopped at (%a+)")
  if at and TIMES[at] then G.window = { [TIMES[at]] = true }; G.inspected = true end

  -- the portraits and the keypad
  if l:find("^Four portraits hang here") or l:find("portraits hang here") then G.portraits = {} end
  local pname, digit = l:match("^  (.-), capsule (%d)$")
  if pname then G.portraits[#G.portraits + 1] = { name = pname, digit = digit } end
  local plaque = l:match("^A brass plaque below: (.+)$")
  if plaque then
    G.plaque = plaque
    G.code = G.codeFromPortraits(G.portraits, plaque)
    if G.code then info("green", "Lab code: " .. G.code .. " (press it in the Lab Vestibule)")
    else info("yellow", "Couldn't read the plaque: " .. plaque .. " - open the lab by hand"); G.labWrong = true end
  end
  if l:find("^The keypad chimes") then G.open.lab = true; G.unsearched["Underground Lab"] = true end
  if l:find("^The keypad buzzes") then info("red", "Wrong lab code " .. tostring(G.code) .. " - check the plaque"); G.code = nil; G.labWrong = true end

  -- gravity, lights, the voice lock
  if l:find("Gravity Chamber winds down") then
    G.gravityShut, G.open.gravity = true, true
    G.unsearched["Gravity Chamber"] = true
  end
  if l:find("^You take a flashlight") then G.flashlight = true end
  if l:find("^The voice lock chimes green") then G.open.suite = true; G.unsearched["Bulma's Suite"] = true end

  -- questioning and confronting
  local pale = l:match("^(.-) sees .* goes pale%.")
  if pale and G.secrets[pale] then G.secrets[pale].confronted = true end

  -- the cake and the analyzer
  local plated, how = l:match("checks her list: (.-) (%a+) the cake")
  if plated then
    G.traits[plated] = G.traits[plated] or {}
    G.traits[plated].cake = how == "refused" and "refused" or "ate"
    G.plated = plated
  end
  local an, verdict = l:match("over evidence #(%d+): (%u+)")
  if an then
    local e = G.evidence[tonumber(an)]
    if e then e.status = verdict:lower() end
    G.analyzed = tonumber(an)
    G.analyses = 0
  end

  -- `accuse` with no words
  if l:find("^Accuse in one line") then B.accuse = "head"; G.akw.suspects, G.akw.weapons, G.akw.rooms = {}, {}, {} end
  if B.accuse then
    local fmt = l:match("^  (accuse <suspect>.*)$")
    if fmt then G.akw.format = fmt end
    local key, words = l:match("^(%a+):%s+(.+)$")
    if key == "Suspects" or key == "Weapons" or key == "Rooms" then B.accuse = key:lower()
    elseif key then B.accuse = "other" end
    if not key and B.accuse ~= "head" and B.accuse ~= "other" then words = trim(l) end
    if key and key ~= "Suspects" and key ~= "Weapons" and key ~= "Rooms" then words = nil end
    if words and (B.accuse == "suspects" or B.accuse == "weapons" or B.accuse == "rooms") then
      for word in words:gmatch("%S+") do table.insert(G.akw[B.accuse], word) end
    end
    if l:find("^Findings:") then B.accuse = nil; G.emit("accuse") end
  end

  -- the end
  local verdict2 = l:match("^Case closed: (.+)$")
  if verdict2 then
    info("green", "Case closed: " .. verdict2)
    G.running = false
    clearWait()
  end
  if l:find("Jaco will have a new case for you in twenty minutes") then
    tempTimer(20 * 60, function() info("green", "Jaco has a new case: say case to him on the Front Steps") end)
  end

  check(l)
end

-- ---------------------------------------------------------------- solving
-- Which way a piece of evidence points: category and value, matched against the guest table.
function G.classify(text)
  local t = text:lower()
  if t:find("footprint") or t:find("tread") or t:find("boot") or t:find("step") then
    if t:find("heavy") or t:find("deep") then return "tread", "heavy" end
    if t:find("light") then return "tread", "light" end
  end
  if t:find("hair") then
    if t:find("not dark") or t:find("fair") or t:find("blond") or t:find("pale") or t:find("grey") or t:find("white") then
      return "hair", "not dark"
    end
    if t:find("dark") or t:find("black") then return "hair", "dark" end
    return "hair", "not dark"
  end
  if t:find("scorch") or t:find("singe") or t:find("smoking") or t:find("flar") then return "ki", "flaring" end
  if t:find("ki sense") or t:find("so still") or t:find("quiet") then return "ki", "quiet" end
  if t:find("untouched") or t:find("never lifted") or t:find("refused") then return "cake", "refused" end
  if t:find("frosting") or t:find("crumb") or t:find("cake") then return "cake", "ate" end
end

-- Mark each piece of evidence: planted, genuine, contested (two pieces disagree), ok, unknown
function G.weighEvidence()
  local values = {}
  for _, e in pairs(G.evidence) do
    e.cat, e.val = G.classify(e.text)
    if e.cat and e.status ~= "planted" then
      values[e.cat] = values[e.cat] or {}
      values[e.cat][e.val] = (values[e.cat][e.val] or 0) + 1
      if e.status == "genuine" then values[e.cat].genuine = e.val end
    end
  end
  for _, e in pairs(G.evidence) do
    if e.status == "planted" then e.state = "planted"
    elseif not e.cat then e.state = "unknown"
    else
      local v = values[e.cat]
      local kinds = 0
      for k in pairs(v) do if k ~= "genuine" then kinds = kinds + 1 end end
      if v.genuine then e.state = (v.genuine == e.val) and "genuine" or "planted"
      elseif kinds > 1 then e.state = "contested"
      else e.state = "ok" end
    end
  end
end

-- Where `s` was at `t`, checked against the witnesses, the seating chart and the door log.
-- Returns rank (0 seen ... 3 lied), short tag and why.
function G.alibi(s, t)
  local at = G.statements[t] or {}
  local st = at[s]
  if not st then return 2, "?", "no statement yet" end
  local R = st.room
  local seen, against = {}, {}
  for w in pairs(G.witnesses) do
    local ws = at[w]
    if w ~= s and ws and ws.room == R then
      if has(ws.with, s) then seen[#seen + 1] = w
      else against[#against + 1] = w .. " was in the " .. R .. " and didn't see them" end
    end
  end
  local chart = G.chart[t]
  if chart then
    if chart[s] and R ~= G.FEAST_ROOM then against[#against + 1] = "the seating chart puts them in the " .. G.FEAST_ROOM
    elseif chart[s] then seen[#seen + 1] = "the seating chart"
    elseif R == G.FEAST_ROOM then against[#against + 1] = "not on the seating chart" end
  end
  local heads = G.log[t] and G.log[t][R]
  local claim = 0
  for _, x in pairs(at) do if x.room == R then claim = claim + 1 end end
  if type(heads) == "number" and claim > heads and #seen == 0 then
    against[#against + 1] = ("the door log counts %d in the %s, %d say they were there"):format(heads, R, claim)
  end
  local where = "the " .. R
  if #against > 0 then return 3, "LIED", where .. ": " .. table.concat(against, "; ") end
  if #seen > 0 then return 0, "seen", where .. ", seen by " .. table.concat(seen, ", ") end
  if type(heads) == "number" and claim == heads then return 1, "fits", where .. ", only suspects back it but the door log fits" end
  return 2, "alone", where .. ", only suspects back it" .. (heads == "broken" and " (sensor broken)" or "")
end

function G.suspects()
  local out = {}
  for _, g in ipairs(G.guests) do
    if not G.witnesses[g] and (next(G.traits) == nil or G.traits[g]) then out[#out + 1] = g end
  end
  return out
end

-- Times the attack could have been at
function G.crimeTimes()
  local out = {}
  for t = 9, 12 do
    if (not G.window or G.window[t]) and not G.quiet[t] then out[#out + 1] = t end
  end
  return out
end

-- Theft: the capsule rooms `s` says they went to after taking it at `t`
function G.stashFor(s, t)
  local out, seen = {}, {}
  for later = (t or 9) + 1, 12 do
    local st = G.statements[later] and G.statements[later][s]
    if st and G.capsules[st.room] and not seen[st.room] then seen[st.room] = true; out[#out + 1] = st.room end
  end
  return out
end

function G.solve()
  G.weighEvidence()
  local theft = G.case.kind == "theft"
  local times = G.crimeTimes()
  local rows = {}
  for _, s in ipairs(G.suspects()) do
    local tr = G.traits[s] or {}
    local row = { name = s, matches = 0, misses = {}, alibis = {} }
    for n, e in pairs(G.evidence) do
      if (e.state == "ok" or e.state == "genuine") and tr[e.cat] then
        if tr[e.cat] == e.val then row.matches = row.matches + 1
        else row.misses[#row.misses + 1] = "#" .. n .. " " .. e.val .. " " .. e.cat end
      end
    end
    row.rank = -1
    for _, t in ipairs(times) do
      local rank, tag, why = G.alibi(s, t)
      row.alibis[t] = { rank = rank, tag = tag, why = why }
      if rank > row.rank then row.rank, row.time = rank, t end
    end
    row.score = (#row.misses == 0 and 100 or 0) + row.rank * 10 + row.matches
    if theft and next(G.capsules) and row.time then
      -- the thief went to exactly one of the capsule rooms afterwards; the decoys are where they never went
      local n = #G.stashFor(s, row.time)
      row.stash = n
      row.score = row.score + (n == 1 and 5 or (n == 0 and -5 or 0))
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
  local r = { rows = rows, times = times }
  local top = rows[1]
  if not top then return r end
  r.suspect, r.time = top.name, top.time
  r.sure = #top.misses == 0 and top.rank == 3 and (not rows[2] or rows[2].score < top.score)

  -- theft: the stash is the capsule room the thief went to after the theft
  if theft then
    local rooms = G.stashFor(top.name, top.time)
    r.stash = rooms[1]
    if #rooms ~= 1 then
      r.stashGuess = true
      if not r.stash then for room in pairs(G.capsules) do r.stash = r.stash or room end end
    end
  -- the weapon: known, or the one kept where the suspect had been before the attack
  elseif G.weapon then r.weapon = G.weapon
  elseif #G.weaponCands > 0 then
    r.weapon, r.weaponGuess = G.weaponCands[1].name, true
    for _, w in ipairs(G.weaponCands) do
      for t = 9, (r.time or 12) - 1 do
        local st = G.statements[t] and G.statements[t][top.name]
        if st and st.room == w.room then r.weapon = w.name end
      end
    end
  end

  -- what would settle it
  local tr = G.traits[top.name] or {}
  for n, e in pairs(G.evidence) do
    if e.state == "contested" and e.cat == "cake" and not tr.cake and not G.plated then r.plate = top.name end
    if e.state == "contested" and e.cat ~= "cake" and tr[e.cat] and tr[e.cat] ~= e.val and (G.analyses or 0) > 0 then
      r.analyze = n
    end
  end

  r.sure = r.sure and not r.weaponGuess and not r.stashGuess
  r.noStatements = next(G.statements[9] or {}) == nil and next(G.statements[12] or {}) == nil
  if r.noStatements then r.sure = false end
  if theft and r.suspect and r.stash and r.time then
    r.line = ("accuse %s stash %s at %s"):format(guestKw(r.suspect), G.keyword(r.stash, G.akw.rooms), TIME_WORD[r.time])
  elseif not theft and r.suspect and r.weapon and r.time then
    r.line = ("accuse %s with %s at %s"):format(guestKw(r.suspect), G.keyword(r.weapon, G.akw.weapons), TIME_WORD[r.time])
  end
  return r
end

function G.report(r)
  r = r or G.solve()
  cecho("\n<cyan>[gum] The case:\n")
  for _, n in ipairs((function() local k = {} for n in pairs(G.evidence) do k[#k + 1] = n end table.sort(k) return k end)()) do
    local e = G.evidence[n]
    local col = ({ planted = "grey", contested = "yellow", genuine = "green", ok = "white" })[e.state] or "grey"
    cecho(("  <%s>#%d %s  <grey>(%s%s)\n"):format(col, n, e.text, e.state or "?", e.cat and (", " .. e.val .. " " .. e.cat) or ""))
  end
  local tw = {}
  for _, t in ipairs(r.times) do tw[#tw + 1] = TIME_WORD[t] end
  local what
  if G.case.kind == "theft" then
    local caps = {}
    for room in pairs(G.capsules) do caps[#caps + 1] = room end
    table.sort(caps)
    what = "   Stash: " .. (r.stash or "?") .. (r.stashGuess and " (guess)" or "") ..
      (#caps > 0 and ("  <grey>capsules in " .. table.concat(caps, ", ")) or "")
  else
    what = "   Weapon: " .. (r.weapon or "?") .. (r.weaponGuess and " (guess)" or "")
  end
  cecho("  <white>When: " .. (#tw > 0 and table.concat(tw, " or ") or "?") .. what .. "\n")
  for i, row in ipairs(r.rows) do
    if i > 4 then break end
    local col = i == 1 and "green" or "white"
    local a = row.time and row.alibis[row.time]
    cecho(("  <%s>%-13s <grey>%d clue%s%s  %s %s\n"):format(col, row.name, row.matches, row.matches == 1 and "" or "s",
      #row.misses > 0 and (", rules out: " .. table.concat(row.misses, ", ")) or "",
      row.time and TIME_WORD[row.time] or "", a and (a.tag .. ", " .. a.why) or ""))
  end
  if r.noStatements then info("red", "Nobody has been questioned yet: the alibis are empty, so this is only a guess") end
  if r.plate then info("yellow", "The cake clues disagree: plate " .. guestKw(r.plate) .. " in the Kitchen settles it") end
  if r.analyze then info("yellow", "Evidence #" .. r.analyze .. " is the one against " .. r.suspect .. ": analyze " .. r.analyze .. " in the Underground Lab") end
  if r.line then
    info(r.sure and "green" or "yellow", (r.sure and "Solved: " or "Best guess: ") .. r.line .. "   (gum accuse sends it, then accuse yes)")
  else
    info("yellow", "Not enough to name anyone yet")
  end
  return r
end

-- ---------------------------------------------------------------- the legwork
-- What's left to do, by room: { room = { {kind, arg}, ... } }
function G.todo()
  local t, searches = {}, 0
  local function add(room, kind, arg)
    t[room] = t[room] or {}
    t[room][#t[room] + 1] = { kind = kind, arg = arg }
  end
  if G.gravityShut and not G.flashlight then
    add("Hangar", "flashlight")
    return t
  end
  for r in pairs(G.unsearched) do
    if not G.searched[r] and G.EXITS[r] and (G.tries["search " .. r] or 0) < 2 then add(r, "search"); searches = searches + 1 end
  end
  for g in pairs(G.unquestioned) do
    if G.where[g] and (G.tries["question " .. g] or 0) < 2 then add(G.where[g], "question", g) end
  end
  local inspectAt = G.inspectRoom or G.case.scene
  if not G.inspected and inspectAt and G.EXITS[inspectAt] and (G.tries.inspect or 0) < 2 then add(inspectAt, "inspect") end
  if count(G.logsRead) < 4 then add("Inner Hall", "logs") end
  if G.open.lab == false and not G.labWrong then
    if G.code then add("Lab Vestibule", "press") elseif not G.plaque then add("Portrait Gallery", "portraits") end
  end
  if G.open.suite == false and G.phrase then add("Upper Landing East", "phrase") end
  if G.open.gravity == false and searches == 0 then add("Robot Charging Bay", "shut") end
  if searches == 0 then
    local lost = false
    for g in pairs(G.unquestioned) do if not G.where[g] then lost = true end end
    if lost then
      for r in pairs(G.EXITS) do
        if not G.visited[r] and r ~= "Front Steps" and G.path(G.room, r) then add(r, "visit") end
      end
    end
    -- confront last: after every room, the sealed ones included, is searched
    local sealedLeft = (G.open.lab == false and not G.labWrong and (G.code or not G.plaque))
      or G.open.gravity == false or (G.open.suite == false and G.phrase)
    for g, s in pairs(sealedLeft and {} or G.secrets) do
      local where = G.where[g] or s.room
      if not s.confronted and where and (G.tries["confront " .. g] or 0) < 2 then add(where, "confront", g) end
    end
  end
  return t
end

function G.nearest(t)
  if not G.room then return nil end
  local best, bestLen
  for room in pairs(t) do
    local p = G.path(G.room, room)
    if p and (not bestLen or #p < bestLen or (#p == bestLen and room < best)) then best, bestLen = room, #p end
  end
  return best
end

local DO = {}
local function tried(key) G.tries[key] = (G.tries[key] or 0) + 1 end

function DO.search(_, cb)
  local room, misses, busy = G.room, 0, 0
  tried("search " .. room)
  local function go()
    cmd("search", { { "%(evidence #%d+%)", "found" }, { "^Tucked out of sight:", "found" }, { "^The seating chart", "found" },
                    { "still turning this room over", "busy" }, { "This room is done for now", "done" },
                    { "^Nothing is ever hidden in", "done" } }, 5, function(k)
      if k == "found" then misses = 0; later(G.searchDelay, go)
      elseif k == "busy" then
        busy = busy + 1
        if busy > 15 then return cb() end
        later(G.busyDelay, go)
      elseif k == "done" then cb()
      else
        misses = misses + 1
        if misses >= 3 then info("yellow", "No answer to search in the " .. room .. ", moving on"); G.searched[room] = true; return cb() end
        later(1, go)
      end
    end)
  end
  go()
end

function DO.question(g, cb)
  tried("question " .. g)
  cmd("question " .. guestKw(g), { { "^At midnight:", "ok" }, { "^Nobody by that name", "bad" } }, G.stepTimeout, function(k)
    if k == "ok" then G.unquestioned[g] = nil; G.questioned[g] = true
    else info("yellow", "Couldn't question " .. g .. " (" .. k .. ")"); G.where[g] = nil end
    cb()
  end)
end

function DO.inspect(_, cb)
  tried("inspect")
  local c = G.inspectCmd or "inspect remains"
  cmd(c, { { "^Nobody was hurt tonight", "wrong" }, { "heart capsule stopped", "ok" }, { "last telemetry", "ok" }, { "cradle", "ok" } },
    G.stepTimeout, function(k)
    if k == "wrong" then return cb() end      -- the line named the right command and room: the next plan goes there
    G.inspected = true
    cb()
  end)
end

function DO.logs(_, cb)
  local steps = {}
  for t = 9, 12 do
    if not G.logsRead[t] then
      steps[#steps + 1] = function(nxt)
        cmd("read log " .. TIME_WORD[t], { { "@log", "ok" } }, G.stepTimeout, function() G.logsRead[t] = true; nxt() end)
      end
    end
  end
  seq(steps, cb)
end

function DO.portraits(_, cb)
  cmd("study portraits", { { "^The lab keypad takes", "ok" } }, G.stepTimeout, function()
    if not G.plaque then G.plaque = "?" end
    cb()
  end)
end

function DO.press(_, cb)
  cmd("press " .. G.code, { { "^The keypad chimes", "ok" }, { "^The keypad buzzes", "bad" } }, G.stepTimeout, function() cb() end)
end

function DO.phrase(_, cb)
  cmd("say " .. G.phrase, { { "^The voice lock chimes green", "ok" } }, G.stepTimeout, function(k)
    if k ~= "ok" then info("yellow", "The voice lock didn't take '" .. G.phrase .. "'"); G.phrase = nil end
    cb()
  end)
end

function DO.shut(_, cb)
  cmd("shut gravity", { { "Gravity Chamber winds down", "ok" } }, G.stepTimeout, function(k)
    if k ~= "ok" then G.open.gravity = nil; info("yellow", "shut gravity didn't answer - do it by hand") end
    cb()
  end)
end

function DO.flashlight(_, cb)
  cmd("take flashlight", { { "^You take a flashlight", "ok" } }, G.stepTimeout, function() G.flashlight = true; cb() end)
end

function DO.confront(g, cb)
  tried("confront " .. g)
  cmd("confront " .. guestKw(g), { { "goes pale", "ok" }, { "^Nobody by that name", "bad" } }, G.stepTimeout, function(k)
    if k == "ok" then G.secrets[g].confronted = true; G.stale = true end
    later(1, cb)
  end)
end

function DO.visit(_, cb) cb() end

local function doTasks(list, cb)
  local steps = {}
  for _, task in ipairs(list) do
    steps[#steps + 1] = function(nxt) DO[task.kind](task.arg, nxt) end
  end
  seq(steps, cb)
end

local function readNotebook(cb)
  cmd("notebook", { { "@notebook", "ok" } }, G.stepTimeout, function() cb() end)
end

local function readStatements(cb)
  local steps = {}
  for t = 9, 12 do
    steps[#steps + 1] = function(nxt) cmd("notebook " .. t, { { "@statements", "ok" } }, G.stepTimeout, function() nxt() end) end
  end
  seq(steps, cb)
end

local function halt(why)
  G.running = false
  clearWait()
  info("red", "Stopped: " .. why)
end

local plan, finish

plan = function()
  if not G.running then return end
  local t = G.todo()
  local room = G.nearest(t)
  if room then
    G.reread = false
    return G.walk(room, function(ok)
      if not ok then return halt("couldn't reach the " .. room) end
      doTasks(t[room], plan)
    end)
  end
  if G.reread then return finish() end
  G.reread = true
  readNotebook(plan)
end

finish = function()
  info("cyan", "Legwork done: reading every statement again")
  seq({
    readStatements,
    function(nxt) cmd("notebook guests", { { "@guests", "ok" } }, G.stepTimeout, function() nxt() end) end,
    function(nxt) cmd("accuse", { { "@accuse", "ok" } }, G.stepTimeout, function() nxt() end) end,
  }, function()
    local r = G.solve()
    if r.plate then
      return G.walk("Kitchen", function(ok)
        if not ok then return G.done(r) end
        cmd("plate " .. guestKw(r.plate), { { "checks her list", "ok" } }, G.stepTimeout, function() finish() end)
      end)
    end
    if r.analyze and G.open.lab then
      return G.walk("Underground Lab", function(ok)
        if not ok then return G.done(r) end
        cmd("analyze " .. r.analyze, { { "over evidence #", "ok" } }, G.stepTimeout, function() finish() end)
      end)
    end
    G.done(r)
  end)
end

function G.done(r)
  G.running = false
  clearWait()
  G.result = G.report(r)
end

function G.run()
  G.gen = G.gen + 1
  G.running, G.reread = true, false
  info("green", "On the case. gum stop stops; everything found so far is kept.")
  seq({
    function(nxt) cmd("look", { { "@arrived", "ok" } }, G.stepTimeout, function() nxt() end) end,
    function(nxt) cmd("notebook guests", { { "@guests", "ok" } }, G.stepTimeout, function() nxt() end) end,
    readNotebook,
  }, function()
    if not G.room or not G.EXITS[G.room] then return halt("not inside the Briefs house") end
    plan()
  end)
end

function G.stop()
  G.gen = G.gen + 1
  G.running = false
  clearWait()
  info("yellow", "Stopped")
end

-- ---------------------------------------------------------------- `gum` alias
G.HELP = {
  { "gum run",          "Do the legwork: search, question, inspect, door log, sealed rooms, confront, then solve" },
  { "gum stop",         "Stop walking (everything found is kept)" },
  { "gum solve",        "Show the evidence, every suspect's alibi and the accusation it points to" },
  { "gum accuse",       "Send the suggested accusation (you still type accuse yes)" },
  { "gum status",       "What's left: rooms to search, guests to question, sealed rooms, secrets" },
  { "gum go <room>",    "Walk to a room in the house, e.g. gum go kitchen" },
  { "gum reset",        "Forget this case (a new case resets by itself)" },
}

function G.help()
  cecho("\n<cyan>Gumshoe, Jaco's party cases at the Briefs house:\n")
  for _, h in ipairs(G.HELP) do cecho(("  <yellow>%-16s<white>%s\n"):format(h[1], h[2])) end
  cecho("  <grey>Open a case with Jaco on the Front Steps (say case), step inside, then gum run.\n")
end

local function list(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return #out > 0 and table.concat(out, ", ") or "none"
end

function G.status()
  local c = G.case
  cecho("\n<cyan>gum status" .. (G.running and " <green>(running)" or "") .. ":\n")
  cecho("  <white>Case: " .. (c.title or "?") .. (c.minutes and ("  <grey>" .. c.minutes .. " min left") or "") .. "\n")
  cecho("  <white>Room: " .. tostring(G.room) .. "   Evidence: " .. (G.evFound or 0) .. " of " .. (G.evTotal or "?") .. "\n")
  local left = {}
  for r in pairs(G.unsearched) do if not G.searched[r] then left[r] = true end end
  cecho("  <white>To search: " .. list(left) .. "\n")
  cecho("  <white>To question: " .. list(G.unquestioned) .. "\n")
  local sealed = {}
  for lock, room in pairs(G.SEALED) do sealed[room .. " " .. (G.open[lock] == true and "open" or G.open[lock] == false and "sealed" or "?")] = true end
  cecho("  <white>Sealed rooms: " .. list(sealed) .. (G.code and ("  code " .. G.code) or "") .. (G.phrase and ("  phrase '" .. G.phrase .. "'") or "") .. "\n")
  local sec = {}
  for g, s in pairs(G.secrets) do sec[g .. (s.confronted and " (confronted)" or (" in the " .. tostring(s.room)))] = true end
  cecho("  <white>Secrets: " .. list(sec) .. "\n")
end

function G.go(where)
  local want = where:lower()
  local match
  for r in pairs(G.EXITS) do
    if r:lower() == want then match = r break end
    if r:lower():find(want, 1, true) and (not match or #r < #match) then match = r end
  end
  if not match then return info("yellow", "No room called '" .. where .. "'") end
  G.gen = G.gen + 1
  G.running = true
  G.walk(match, function(ok)
    G.running = false
    if ok then info("green", "In the " .. match) end
  end)
end

function G.command(c, arg)
  if c == nil or c == "help" then G.help()
  elseif c == "run" or c == "start" then G.run()
  elseif c == "stop" then G.stop()
  elseif c == "solve" then G.result = G.report()
  elseif c == "accuse" then
    local r = G.solve()
    if not r.line then return info("yellow", "Not enough to accuse anyone yet: gum solve") end
    local fmt = G.akw.format
    if fmt and not fmt:find("with <weapon> at <time>$") and not fmt:find("stash <room> at <time>$") then
      return info("yellow", "This case wants: " .. fmt .. " - accuse by hand")
    end
    send(r.line, false)
  elseif c == "status" then G.status()
  elseif c == "go" and arg then G.go(arg)
  elseif c == "reset" then G.newCase(); info("white", "Case forgotten")
  else info("yellow", "Unknown command '" .. tostring(c) .. "'. Type gum help") end
end
