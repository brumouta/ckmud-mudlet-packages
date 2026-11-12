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
G.difficulty  = G.difficulty or "hard" -- `gum case` with no difficulty
G.capsuleCmd  = G.capsuleCmd or "use mansion"                  -- the return capsule: to the Briefs Family Garden
G.instantCmd  = G.instantCmd or "focus 'instant' bulma"        -- if there's no capsule: Bulma's Workshop, then pursue jaco

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
  G.cover = nil            -- accomplices: { culprit, coverer } once the coverer owns up
  G.card = nil             -- the room a Phantom calling card turned up in (G.cards, the casebook count, outlives cases)
  G.partyRooms = {}        -- theft: the rooms a stash can be in
  G.questioned = {}        -- guests this script questioned
  G.guests = {}            -- every guest's name, in the intro's order
  G.witnesses = {}         -- name -> true: never the culprit, never lie
  G.traits = {}            -- name -> { ki, tread, hair, cake }
  G.statements = {}        -- [time][name] = { room, with = {...}, first = room they first claimed }
  G.window = nil           -- [time] = true: when the stand-in stopped
  G.quiet = {}             -- [time] = true: the log says all was quiet
  G.delay = nil            -- delayed sabotage: chimes between rigging and going off
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
  G.plateTried, G.analyzeTried, G.darkWarned = false, false, false
  G.akw = { suspects = {}, weapons = {}, rooms = {}, format = nil }  -- keywords from `accuse`
  G.tries = {}
end
-- Installing a newer version mid-case keeps the case but must add any field it didn't have
function G.upgrade()
  local old = {}
  for k, v in pairs(G) do if type(v) ~= "function" then old[k] = v end end
  local oldCase, oldAkw, oldOpen = G.case, G.akw, G.open
  G.newCase()
  for k, v in pairs(old) do G[k] = v end
  local fresh = { case = { kind = "murder", wrong = 0 }, akw = { suspects = {}, weapons = {}, rooms = {} }, open = {} }
  G.case, G.akw, G.open = oldCase or fresh.case, oldAkw or fresh.akw, oldOpen or fresh.open
  for k, v in pairs(fresh.case) do if G.case[k] == nil then G.case[k] = v end end
  for k, v in pairs(fresh.akw) do if G.akw[k] == nil then G.akw[k] = v end end
end
if not G.case then G.newCase() else G.upgrade() end
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
  local old = G.statements[t][name]
  local st = { room = B.room, with = with, first = first and roomName(first) or nil }
  -- keep who they first claimed to be with (the table only names the first room)
  if st.first and old then
    if old.firstWith then st.firstWith = old.firstWith
    elseif old.room == st.first then st.firstWith = old.with end
  end
  G.statements[t][name] = st
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

local CHIMES = { one = 1, two = 2, three = 3 }
-- "Its dial reads set two chimes before it fired" -> 2
local function readDelay(text)
  local n = text:match("set (%a+) chimes? before it fired")
  if n and CHIMES[n:lower()] then G.delay = CHIMES[n:lower()]; G.case.kind = "sabotage"; return true end
end

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

-- 'In the Grand Hall, with Emperor Pilaf. Just being polite...' -> { room, with = { ... } }
function G.parseAnswer(said)
  local room, rest = said:match("^In the (.-)([,.].*)$")
  if not room then return nil end
  local with = {}
  local list = rest:match("^, with (.*)$")
  if list then
    -- the sentence ends at the first ". " that isn't Mr. / Dr. / Mrs.
    local masked = list:gsub("(%u%l?%l?)%. ", function(w)
      if w == "Mr" or w == "Dr" or w == "Mrs" then return w .. "# " end
    end)
    masked = masked:match("^(.-)%.[%s\"]") or masked:match("^(.-)%.$") or masked
    with = split((masked:gsub("#", ".")))
  end
  return { room = roomName(room), with = with }
end

local function parseLead(done, n, text)
  B.section = n
  if n == 1 then
    if done then
      G.inspected = true
      setWindow((text:match("^When: ([^;]*)") or ""))
      for q in text:gmatch("quiet at (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
      for q in text:gmatch("still in its cradle at (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
      -- "the cradle was found empty by midnight": already gone at that chime, so it wasn't taken then
      for q in text:gmatch("found empty by (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
      -- lights out: "the party log says the alarm was up by eleven": it had happened before then
      for q in text:gmatch("alarm was up by (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
      -- sabotage: "the party log says nothing had gone off at eleven. The delay timer says it was set two chimes before it fired."
      for q in text:gmatch("nothing had gone off at (%a+)") do if TIMES[q] then G.quiet[TIMES[q]] = true end end
      readDelay(text)
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
  if kind then
    kind = kind:lower()
    G.case.kind = (kind == "delayed") and "sabotage" or kind
    return
  end
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
  -- after a plate the table says "Cake: Yajirobe ate cake. Nobody else's plate is known."
  local cp, cw = l:match("^Cake: (.-) (ate) cake")
  if not cp then cp, cw = l:match("^Cake: (.-) (refused) ") end
  if cp and cp ~= "only Mrs. Briefs' stand-in knows." then
    G.traits[cp] = G.traits[cp] or {}
    G.traits[cp].cake = cw
    G.plated = cp
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
  -- "Difficulty: Hard. One more guest lies, the lab analyzer is off, and Garter's door log has a second broken sensor."
  local diff = l:match("^Difficulty: (%a+)%.")
  if diff then G.case.difficulty = diff end
  if l:find("^Difficulty: .*analyzer is off") then G.case.noAnalyzer = true end
  local caseText = l:match("^The case: (.+)$")
  if caseText then
    G.case.title = caseText
    local scene = caseText:match("in the (.-)%.")
    G.case.scene = scene and roomName(scene) or nil
  end
  if l:find("^Theft: ") then G.case.kind = "theft" end
  if l:find("^Accomplices: ") then G.case.kind = "accomplices" end
  if l:find("^Delayed sabotage: ") then G.case.kind = "sabotage" end
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
  if stillAt and TIMES[stillAt] and (l:find("still") or l:find("nothing had gone off")) then G.quiet[TIMES[stillAt]] = true end
  -- delayed sabotage: the timer at the scene, and the weapon's empty case
  if l:find("delay timer") then readDelay(l) end
  local cw, cr = l:match("the empty case of the (.-), its foam.-keeps it in the (.-), so")
  if cw then G.weapon = cw; G.weaponCands = { { name = cw, room = roomName(cr) } }; G.case.kind = "sabotage" end
  -- "The stand-ins' party log: by midnight, Dr. Briefs had found the cradle in the Study empty."
  local emptyBy = l:match("party log: by (%a+), .*cradle.* empty")
  if emptyBy and TIMES[emptyBy] then G.quiet[TIMES[emptyBy]] = true end
  -- "The stand-ins' party log: by eleven, the alarm had already gone up in the Menagerie Yard."
  local upBy = l:match("party log: by (%a+), the alarm had already gone up")
  if upBy and TIMES[upBy] then G.quiet[TIMES[upBy]] = true end
  if l:find("cradle") and not emptyBy and not l:find("still in its cradle") and not l:find("inspect cradle") and #timesIn(l) > 0 then
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
  -- the lights are out and we can't see: get a light before searching on
  if l:find("^It is pitch dark%. You feel around") then G.gravityShut, G.flashlight = true, false end
  if l:find("lights? .*come back on") or l:find("^You reset the breaker") then G.gravityShut = false; G.open.gravity = false end
  if l:find("^The voice lock chimes green") then G.open.suite = true; G.unsearched["Bulma's Suite"] = true end

  -- questioning and confronting: the answers go straight into the alibis
  local teller = l:match("^(.-) tells you, '")
  if teller and has(G.guests, teller) then B.answer, B.confession = teller, false end
  local pale = l:match("^(.-) sees .* goes pale%.")
  if pale then
    if G.secrets[pale] then G.secrets[pale].confronted = true end
    if has(G.guests, pale) then B.answer, B.confession = pale, true end
  end
  -- accomplices: the one who covered owns up when confronted
  -- "I was never in the Dining Room with Emperor Pilaf. They asked me to say we were together, and I covered for them."
  local _, covered = l:match("I was never in the (.-) with (.-)%. They asked me to say we were together")
  if covered and B.answer then
    G.cover = { culprit = covered, coverer = B.answer }
    G.case.kind = "accomplices"
  end
  local at, said = l:match('^At (%a+): "(.*)$')
  if at and TIMES[at] and B.answer then
    local st = G.parseAnswer(said)
    if st then
      local t = TIMES[at]
      G.statements[t] = G.statements[t] or {}
      local old = G.statements[t][B.answer]
      if B.confession and old and old.room ~= st.room then st.first, st.firstWith = old.first or old.room, old.firstWith or old.with end
      -- a notebook table already read is the game's own summary; an answer only fills gaps or corrects a confession
      if not old or B.confession then G.statements[t][B.answer] = st end
      if t == 12 then G.questioned[B.answer] = true; G.unquestioned[B.answer] = nil end
    end
  elseif not covered and not l:find("^So that is where I really was") and not l:find("^\"So that is where") and not teller and not pale then
    B.answer = nil
  end

  -- the cake and the analyzer
  -- "Yamcha refused the cake." / "Yajirobe ate a slice of cake."
  local plated, how = l:match("checks her list: (.-) (refused) ")
  if not plated then plated, how = l:match("checks her list: (.-) (ate) ") end
  if plated then
    G.traits[plated] = G.traits[plated] or {}
    G.traits[plated].cake = how
    G.plated = plated
  end
  -- the one peek is used up, whatever this script knows
  if l:find("One peek at my list per party") then G.plated = G.plated or true end
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

  -- the Phantom's calling cards: kept when the case is solved, three summon him
  if l:find("^Tucked out of sight: a black calling card") then
    G.card = G.room or "house"
    info("magenta", "A Phantom calling card" .. (G.room and (" in the " .. G.room) or "") .. ". Solve the case in time and it's yours"
      .. (G.cards and (" (that makes " .. (G.cards + 1) .. ")") or ""))
  end
  local cards = l:match("^%s*Calling cards:%s+(%d+)")
  if cards then G.cards = tonumber(cards) end

  -- the end
  local verdict2 = l:match("^Case closed: (.+)$")
  if verdict2 then
    info("green", "Case closed: " .. verdict2)
    local lost = verdict2:lower():find("cold") or verdict2:lower():find("fail") or verdict2:lower():find("lost")
    if G.card and not lost then
      G.cards = (G.cards or 0) + 1
      info("magenta", "The Phantom's calling card is yours: " .. G.cards .. (G.cards >= 3 and " held. Enough to summon the Phantom!" or " of 3"))
      G.card = nil
    end
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
    -- too many claim the room: if the extra ones are exactly those nobody else there names,
    -- only they lied, and the log fits the rest
    local unnamed, sUnnamed = 0, false
    for g, x in pairs(at) do
      if x.room == R then
        local named = false
        for o, y in pairs(at) do if o ~= g and y.room == R and has(y.with, g) then named = true end end
        if not named then unnamed = unnamed + 1; if g == s then sUnnamed = true end end
      end
    end
    if unnamed > 0 and unnamed <= claim - heads and not sUnnamed then
      claim = heads
    else
      against[#against + 1] = ("the door log counts %d in the %s, %d say they were there"):format(heads, R, claim)
        .. (sUnnamed and ", and nobody there names them" or "")
    end
  end
  local where = "the " .. R
  if #against > 0 then return 3, "LIED", where .. ": " .. table.concat(against, "; ") end
  if #seen > 0 then return 0, "seen", where .. ", seen by " .. table.concat(seen, ", ") end
  -- they name people in that room who name each other but not them (a confession nobody there backs)
  local snub = {}
  for _, o in ipairs(st.with or {}) do
    local os = at[o]
    if os and os.room == R and #(os.with or {}) > 0 and not has(os.with, s) then snub[#snub + 1] = o end
  end
  if #snub > 0 and #snub == #(st.with or {}) then
    local why = where .. ": " .. table.concat(snub, " and ") .. " were there and don't name them"
    -- a confession nobody backs, after a first story that was already a proven lie: lied twice
    local F = st.first
    if F and F ~= R then
      local caught
      for w in pairs(G.witnesses) do
        local ws = at[w]
        if not caught and w ~= s and ws and ws.room == F and not has(ws.with, s) then caught = w .. " was in the " .. F .. " and didn't see them" end
      end
      if not caught and chart and F == G.FEAST_ROOM and not chart[s] then caught = "the seating chart leaves them out of the " .. F end
      if caught then return 3, "LIED", why .. "; first said the " .. F .. ", but " .. caught end
    end
    return 2.5, "unbacked", why
  end
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

-- Times it could have gone off
function G.fireTimes()
  local out = {}
  for t = 9, 12 do
    if (not G.window or G.window[t]) and not G.quiet[t] then out[#out + 1] = t end
  end
  return out
end

-- Times the culprit acted: when it happened, or for a delayed sabotage, when it was rigged
-- (the timer's chimes before it went off; without the timer, any hour before it could have)
function G.crimeTimes()
  local fire = G.fireTimes()
  if G.case.kind ~= "sabotage" then return fire end
  local out, seen = {}, {}
  if G.delay then
    for _, t in ipairs(fire) do
      local r = t - G.delay
      if r >= 9 and not seen[r] then seen[r] = true; out[#out + 1] = r end
    end
  else
    for t = 9, (fire[#fire] or 12) - 1 do out[#out + 1] = t end
  end
  table.sort(out)
  return out
end

-- Sabotage: did `s` say they were in the weapon's room before rigging it at `t`?
function G.tookWeapon(s, t, room)
  for h = 9, t - 1 do
    local st = G.statements[h] and G.statements[h][s]
    if st and (st.room == room or st.first == room) then return true end
  end
  return false
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

-- Accomplices: the two swore they were together at the time, and each named the other.
-- The partner is the suspect whose first story at that hour puts them in the culprit's room, naming each other.
function G.partnerOf(culprit, t)
  local st = G.statements[t] or {}
  local mine = st[culprit]
  if not mine then return nil end
  local room, with = mine.first or mine.room, mine.firstWith or mine.with or {}
  local best, bestScore
  for _, s in ipairs(G.suspects()) do
    local o = st[s]
    if s ~= culprit and o and (o.first or o.room) == room then
      local score = 0
      if has(with, s) then score = score + 1 end
      if has(o.firstWith or o.with or {}, culprit) then score = score + 1 end
      if o.first then score = score + 1 end   -- changed their story: a confessed cover
      if not bestScore or score > bestScore then best, bestScore = s, score end
    end
  end
  return best
end

function G.solve()
  if G.case.noAnalyzer then G.analyses = 0 end   -- Hard: the lab analyzer is off
  G.weighEvidence()
  local theft = G.case.kind == "theft"
  local times = G.crimeTimes()
  local rows = {}
  for _, s in ipairs(G.suspects()) do
    local tr = G.traits[s] or {}
    local row = { name = s, matches = 0, misses = {}, missN = {}, alibis = {} }
    for n, e in pairs(G.evidence) do
      if (e.state == "ok" or e.state == "genuine") and tr[e.cat] then
        if tr[e.cat] == e.val then row.matches = row.matches + 1
        else row.misses[#row.misses + 1] = "#" .. n .. " " .. e.val .. " " .. e.cat; row.missN[#row.missN + 1] = n end
      end
    end
    row.rank = -1
    for _, t in ipairs(times) do
      local rank, tag, why = G.alibi(s, t)
      row.alibis[t] = { rank = rank, tag = tag, why = why }
      if rank > row.rank then row.rank, row.time = rank, t end
    end
    -- "find the one nobody saw" first; a clue that doesn't fit may be planted, so it only costs points
    row.score = row.rank * 100 + row.matches * 10 - #row.misses * 15
    if theft and next(G.capsules) and row.time then
      -- the thief went to exactly one of the capsule rooms afterwards; the decoys are where they never went
      local n = #G.stashFor(s, row.time)
      row.stash = n
      row.score = row.score + (n == 1 and 5 or (n == 0 and -5 or 0))
    end
    -- sabotage: whoever rigged it took the weapon from its room earlier in the night
    local wroom = G.case.kind == "sabotage" and #G.weaponCands == 1 and G.weaponCands[1].room
    if wroom and row.time then
      row.tookWeapon = G.tookWeapon(s, row.time, wroom)
      row.score = row.score + (row.tookWeapon and 30 or 0)
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
  local r = { rows = rows, times = times }
  local top = rows[1]
  if not top then return r end
  r.suspect, r.time = top.name, top.time
  r.sure = #top.misses == 0 and top.rank == 3 and (not rows[2] or rows[2].rank < 3)

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

  -- what would settle it: first a clue against the one nobody saw (the lab says if it was planted)
  if #top.missN > 0 and (G.analyses or 0) > 0 then r.analyze = top.missN[1] end
  local tr = G.traits[top.name] or {}
  for n, e in pairs(G.evidence) do
    if e.state == "contested" and e.cat == "cake" and not tr.cake and not G.plated then r.plate = top.name end
    if not r.analyze and e.state == "contested" and e.cat ~= "cake" and tr[e.cat] and tr[e.cat] ~= e.val and (G.analyses or 0) > 0 then
      r.analyze = n
    end
  end

  -- accomplices: who did it, and who covered for them
  if G.case.kind == "accomplices" then
    if G.cover and has(G.guests, G.cover.culprit) then
      r.suspect, r.partner = G.cover.culprit, G.cover.coverer
    elseif r.suspect and r.time then
      r.partner = G.partnerOf(r.suspect, r.time)
    end
    if not r.partner then r.sure = false end
  end

  r.sure = r.sure and not r.weaponGuess and not r.stashGuess
  r.noStatements = next(G.statements[9] or {}) == nil and next(G.statements[12] or {}) == nil
  if r.noStatements then r.sure = false end
  if theft and r.suspect and r.stash and r.time then
    r.line = ("accuse %s stash %s at %s"):format(guestKw(r.suspect), G.keyword(r.stash, G.akw.rooms), TIME_WORD[r.time])
  elseif G.case.kind == "accomplices" then
    if r.suspect and r.partner and r.weapon and r.time then
      r.line = ("accuse %s and %s with %s at %s"):format(guestKw(r.suspect), guestKw(r.partner), G.keyword(r.weapon, G.akw.weapons), TIME_WORD[r.time])
    end
  elseif G.case.kind == "sabotage" then
    if r.suspect and r.weapon and r.time then
      r.line = ("accuse %s with %s rigged at %s"):format(guestKw(r.suspect), G.keyword(r.weapon, G.akw.weapons), TIME_WORD[r.time])
    end
    if not G.delay then r.sure = false end
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
    if G.case.kind == "accomplices" then
      what = what .. "   Covered by: " .. (r.partner or "?") .. (G.cover and " (confessed)" or "")
    end
  end
  local when = (#tw > 0 and table.concat(tw, " or ") or "?")
  if G.case.kind == "sabotage" then
    local fw = {}
    for _, t in ipairs(G.fireTimes()) do fw[#fw + 1] = TIME_WORD[t] end
    when = "rigged at " .. when .. " (went off at " .. (#fw > 0 and table.concat(fw, " or ") or "?")
      .. (G.delay and (", timer " .. G.delay .. " chime" .. (G.delay == 1 and "" or "s")) or ", timer not found yet") .. ")"
  end
  cecho("  <white>When: " .. when .. what .. "\n")
  for i, row in ipairs(r.rows) do
    if i > 4 then break end
    local col = i == 1 and "green" or "white"
    local a = row.time and row.alibis[row.time]
    cecho(("  <%s>%-13s <grey>%d clue%s%s  %s %s\n"):format(col, row.name, row.matches, row.matches == 1 and "" or "s",
      #row.misses > 0 and (", doesn't fit: " .. table.concat(row.misses, ", ")) or "",
      row.time and TIME_WORD[row.time] or "", a and (a.tag .. ", " .. a.why) or ""))
  end
  if r.noStatements then info("red", "Nobody has been questioned yet: the alibis are empty, so this is only a guess") end
  if r.plate then info("yellow", "The cake clues disagree: plate " .. guestKw(r.plate) .. " in the Kitchen settles it") end
  if r.analyze then info("yellow", "Evidence #" .. r.analyze .. " doesn't fit " .. r.suspect .. " - it may be planted: analyze " .. r.analyze .. " in the Underground Lab") end
  if r.line then
    info(r.sure and "green" or "yellow", (r.sure and "Solved: " or "Best guess: ") .. r.line .. "   (gum accuse sends it, then accuse yes)")
  else
    info("yellow", "Not enough to name anyone yet")
  end
  if G.card then info("magenta", "A Phantom calling card is waiting on this case: solve it in time and it's yours") end
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
    -- the game's two ways to see: a flashlight from the Hangar, or the breaker in the Robot Charging Bay
    -- resetting the breaker re-seals the Gravity Chamber, so only once that room is searched
    local chamberDone = G.searched["Gravity Chamber"] or not G.unsearched["Gravity Chamber"]
    if (G.tries.flashlight or 0) < 2 then add("Hangar", "flashlight")
    elseif chamberDone and (G.tries.breaker or 0) < 2 then add("Robot Charging Bay", "breaker")
    elseif not G.darkWarned then
      G.darkWarned = true
      info("yellow", "It's dark and the flashlight won't come: take flashlight in the Hangar by hand, then gum run")
    end
    return t
  end
  if G.onlyQuestions then
    local lost = false
    for g in pairs(G.unquestioned) do
      if G.where[g] and (G.tries["question " .. g] or 0) < 2 then add(G.where[g], "question", g)
      elseif not G.where[g] then lost = true end
    end
    if lost then
      for r in pairs(G.EXITS) do
        if not G.visited[r] and r ~= "Front Steps" and G.path(G.room, r) then add(r, "visit") end
      end
    end
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
                    { "^Nothing is ever hidden in", "done" }, { "^It is pitch dark", "dark" } }, 5, function(k)
      if k == "dark" then
        -- not a real try: fetch a light, then this room comes up again
        G.tries["search " .. room] = (G.tries["search " .. room] or 1) - 1
        return cb()
      elseif k == "found" then misses = 0; later(G.searchDelay, go)
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
  tried("flashlight")
  cmd("take flashlight", { { "^You take a flashlight", "ok" }, { "already .*flashlight", "ok" } }, G.stepTimeout, function(k)
    if k == "ok" then G.flashlight = true end
    cb()
  end)
end

function DO.breaker(_, cb)
  tried("breaker")
  cmd("reset breaker", { { "^You .*breaker", "ok" }, { "lights? .*come back on", "ok" } }, G.stepTimeout, function(k)
    -- the lights come back and the Gravity Chamber seals again
    if k == "ok" then G.gravityShut = false; G.open.gravity = false end
    cb()
  end)
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
    -- each check at most once a case, so an answer this script misreads can't loop
    if r.plate and G.plateTried then r.plate = nil end
    if r.analyze and G.analyzeTried then r.analyze = nil end
    if r.plate then
      G.plateTried = true
      return G.walk("Kitchen", function(ok)
        if not ok then return G.done(r) end
        cmd("plate " .. guestKw(r.plate), { { "checks her list", "ok" }, { "One peek at my list", "ok" } }, G.stepTimeout, function() finish() end)
      end)
    end
    if r.analyze and G.open.lab then
      G.analyzeTried = true
      return G.walk("Underground Lab", function(ok)
        if not ok then return G.done(r) end
        cmd("analyze " .. r.analyze, { { "over evidence #", "ok" } }, G.stepTimeout, function() finish() end)
      end)
    end
    G.done(r)
  end)
end

G.finish = function() return finish() end

function G.done(r)
  G.running = false
  clearWait()
  G.result = G.report(r)
end

function G.run(onlyQuestions)
  G.gen = G.gen + 1
  G.running, G.reread, G.onlyQuestions = true, false, onlyQuestions
  info("green", onlyQuestions and "Questioning everyone left. gum stop stops." or "On the case. gum stop stops; everything found so far is kept.")
  seq({
    function(nxt) cmd("look", { { "@arrived", "ok" } }, G.stepTimeout, function() nxt() end) end,
    function(nxt) cmd("notebook guests", { { "@guests", "ok" } }, G.stepTimeout, function() nxt() end) end,
    readNotebook,
  }, function()
    if not G.room or not G.EXITS[G.room] then return halt("not inside the Briefs house") end
    plan()
  end)
end

-- `gum solve`: read the notebook, the statements and the accuse words fresh, then solve
function G.refreshAndSolve()
  G.gen = G.gen + 1
  G.running = true
  local steps = { readNotebook, readStatements }
  if next(G.traits) == nil then
    steps[#steps + 1] = function(nxt) cmd("notebook guests", { { "@guests", "ok" } }, G.stepTimeout, function() nxt() end) end
  end
  steps[#steps + 1] = function(nxt) cmd("accuse", { { "@accuse", "ok" } }, G.stepTimeout, function() nxt() end) end
  seq(steps, function() G.done(G.solve()) end)
end

function G.stop()
  G.gen = G.gen + 1
  G.running = false
  clearWait()
  info("yellow", "Stopped")
end

-- ---------------------------------------------------------------- `gum` alias
G.HELP = {
  { "gum case [diff]",  "Go to Jaco (return capsule, else instant to Bulma and pursue Jaco) and say case (default hard)" },
  { "gum run",          "Do the legwork: search, question, inspect, door log, sealed rooms, confront, then solve" },
  { "gum question",     "Only question everyone not questioned yet (walking to find them), then solve" },
  { "gum stop",         "Stop walking (everything found is kept)" },
  { "gum solve",        "Re-read the notebook and statements, then show the evidence, the alibis and the accusation" },
  { "gum accuse",       "Send the suggested accusation (you still type accuse yes)" },
  { "gum status",       "What's left: rooms to search, guests to question, sealed rooms, secrets" },
  { "gum go <room>",    "Walk to a room in the house, e.g. gum go kitchen" },
  { "gum reset",        "Forget this case (a new case resets by itself)" },
}

function G.help()
  cecho("\n<cyan>Gumshoe, Jaco's party cases at the Briefs house:\n")
  for _, h in ipairs(G.HELP) do cecho(("  <yellow>%-16s<white>%s\n"):format(h[1], h[2])) end
  cecho("  <grey>gum case to open one with Jaco, step inside, then gum run.\n")
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
  cecho("  <white>Calling card: " .. (G.card and ("found in the " .. G.card .. ", yours if you solve it") or "none this case")
    .. (G.cards and ("   cards held: " .. G.cards .. (G.cards >= 3 and "" or " of 3") .. (G.cards >= 3 and " (enough to summon the Phantom)" or "")) or "") .. "\n")
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

-- `gum case [easy|normal|hard]`: get to Jaco on the Front Steps and open a case.
-- Inside the house it walks there. Otherwise the return capsule (Briefs Family Garden, then 6 west),
-- or without one, instant transmission to Bulma (Bulma's Workshop), then pursue jaco.
local NO_CAPSULE = { { "^Briefs Family Garden$", "ok" }, { "^You don't", "no" }, { "^You do not", "no" },
                     { "^Use what", "no" }, { "^You can't", "no" }, { "^Huh", "no" },
                     { "^You can only use", "no" } }
function G.toJaco(diff)
  diff = (diff or G.difficulty):lower()
  if not ({ easy = true, normal = true, hard = true })[diff] then
    return info("yellow", "gum case easy, normal or hard (default " .. G.difficulty .. ")")
  end
  G.gen = G.gen + 1
  G.running = true
  local function sayCase() G.running = false; send("say case " .. diff, false) end
  local function walkIn(first)
    if first then send(first, false) end
    for _ = 1, 6 do send("w", false) end
    expect({ { "^Front Steps$", "ok" } }, 20, function(k)
      if k == "ok" then return sayCase() end
      halt("didn't reach Jaco on the Front Steps")
    end)
  end
  cmd("look", { { "@arrived", "in" } }, 3, function(k)
    if k == "in" and G.room then
      return G.walk("Front Steps", function(ok) if ok then sayCase() else G.running = false end end)
    end
    info("green", "Off to Jaco for a " .. diff .. " case")
    cmd(G.capsuleCmd, NO_CAPSULE, 5, function(k2)
      if k2 == "ok" then return walkIn() end
      info("yellow", "No return capsule: instant transmission to Bulma, then pursue Jaco")
      local function pursueJaco()
        cmd("pursue jaco", { { "^Front Steps$", "ok" } }, 30, function(k4)
          if k4 == "ok" then return sayCase() end
          halt("pursue jaco didn't reach the Front Steps")
        end)
      end
      -- "You failed." means the target is protected against instant transmission: pursue Jaco from here instead
      cmd(G.instantCmd, { { "^Bulma's Workshop$", "ok" }, { "^You failed%.$", "failed" } }, 8, function(k3)
        if k3 ~= "ok" then info("yellow", "Instant transmission to Bulma " .. (k3 == "failed" and "failed" or "didn't land") .. ": pursuing Jaco from here") end
        pursueJaco()
      end)
    end)
  end)
end

function G.command(c, arg)
  if c == nil or c == "help" then G.help()
  elseif c == "run" or c == "start" then G.run()
  elseif c == "question" then G.run(true)
  elseif c == "stop" then G.stop()
  elseif c == "solve" then
    if G.running then G.result = G.report() else G.refreshAndSolve() end
  elseif c == "accuse" then
    local r = G.solve()
    if not r.line then return info("yellow", "Not enough to accuse anyone yet: gum solve") end
    local fmt = G.akw.format
    if fmt and not fmt:find("with <weapon> at <time>$") and not fmt:find("stash <room> at <time>$")
      and not fmt:find("with <weapon> rigged at <time>$") then
      return info("yellow", "This case wants: " .. fmt .. " - accuse by hand")
    end
    send(r.line, false)
  elseif c == "status" then G.status()
  elseif c == "go" and arg then G.go(arg)
  elseif c == "case" then G.toJaco(arg)
  elseif c == "reset" then G.newCase(); info("white", "Case forgotten")
  else info("yellow", "Unknown command '" .. tostring(c) .. "'. Type gum help") end
end
