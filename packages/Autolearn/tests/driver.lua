-- Mudlet environment simulator + Autolearn package smoke test.
-- Runs the real package sources under fengari (Lua 5.3) with stubbed Mudlet APIs.

local ROOT = SRC_ROOT or "src" -- injected by runner.js

---------------------------------------------------------------------------
-- Test bookkeeping
---------------------------------------------------------------------------
local failures = {}
local passes = 0
local function check(cond, msg)
  if cond then
    passes = passes + 1
    print("PASS: " .. msg)
  else
    table.insert(failures, msg)
    print("FAIL: " .. msg)
  end
end

---------------------------------------------------------------------------
-- Lua 5.1 compat + Mudlet utility globals
---------------------------------------------------------------------------
unpack = table.unpack

-- Mudlet runs Lua 5.1, where string.format("%s", nil) is an ERROR; fengari is
-- 5.3 and quietly prints "nil". Enforce the 5.1 behaviour so the simulation
-- catches format bugs that would abort a real render.
local _format = string.format
function string.format(fmt, ...)
  local args = { ... }
  local n = select("#", ...)
  local i = 0
  for spec in fmt:gmatch("%%[-+ #0-9.]*([diouxXeEfgGqsc])") do
    i = i + 1
    if i <= n or args[i] == nil then
      local v = args[i]
      if v == nil then
        error(("bad argument #%d to 'format' (no value)"):format(i + 1), 2)
      end
      if spec == "d" or spec == "i" or spec == "f" then
        if tonumber(v) == nil then
          error(("bad argument #%d to 'format' (number expected, got %s)"):format(i + 1, type(v)), 2)
        end
      end
    end
  end
  return _format(fmt, ...)
end

loadstring = function(s) return load(s) end

local smt = getmetatable("").__index

function smt.split(s, sep)
  sep = sep or " "
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, sep, pos, true)
    if not a then
      table.insert(out, string.sub(s, pos))
      break
    end
    table.insert(out, string.sub(s, pos, a - 1))
    pos = b + 1
  end
  return out
end
function smt.starts(s, p) return string.sub(s, 1, #p) == p end
function smt.ends(s, p) return p == "" or string.sub(s, -#p) == p end
function smt.trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function smt.title(s) return s:sub(1, 1):upper() .. s:sub(2):lower() end

function table.contains(t, v)
  for _, x in pairs(t) do if x == v then return true end end
  return false
end
function table.keys(t)
  local out = {}
  for k in pairs(t) do table.insert(out, k) end
  return out
end
function table.n_union(a, b)
  local out, seen = {}, {}
  for _, v in ipairs(a) do if not seen[v] then seen[v] = true; table.insert(out, v) end end
  for _, v in ipairs(b) do if not seen[v] then seen[v] = true; table.insert(out, v) end end
  return out
end
function table.n_filter(t, fn)
  local out = {}
  for _, v in ipairs(t) do if fn(v) then table.insert(out, v) end end
  return out
end

-- Mudlet's f-string interpolation
function f(s)
  local env = setmetatable({}, { __index = _G })
  local i = 1
  while true do
    local n, v = debug.getlocal(2, i)
    if not n then break end
    if n:sub(1, 1) ~= "(" then env[n] = v end
    i = i + 1
  end
  -- Mudlet's f-strings see the caller's LOCALS and globals, but NOT upvalues
  -- (file-level locals). Resolving them here would hide real "nil" bugs.
  return (s:gsub("%b{}", function(block)
    local expr = block:sub(2, -2)
    local fn, err = load("return " .. expr, "f-expr", "t", env)
    if not fn then error("f parse error in [" .. expr .. "]: " .. tostring(err), 0) end
    local ok, res = pcall(fn)
    if not ok then error("f eval error in [" .. expr .. "]: " .. tostring(res), 0) end
    return tostring(res)
  end))
end

---------------------------------------------------------------------------
-- Mudlet API stubs
---------------------------------------------------------------------------
SENT = {}
MSDP_SENT = {}
LOG = {}
TIMERS = {}
HANDLERS = {}
TRIGGER_STATE = {}
SPEEDWALKS = {}
fake_epoch = 1000000
connected = true

local function log(...)
  local parts = {}
  for _, v in ipairs({ ... }) do table.insert(parts, tostring(v)) end
  table.insert(LOG, table.concat(parts, " "))
end

function cecho(s) log("[cecho]", s) end
function echo(s) log("[echo]", s) end
function display(v) log("[display]", tostring(v)) end
local realprint = print
function print(...) log("[print]", ...) end

function send(cmd, _echo) table.insert(SENT, cmd); log("SEND >", cmd) end
function sendMSDP(...) table.insert(MSDP_SENT, { ... }); log("MSDP >", ...) end

function raiseEvent(event, ...)
  local hs = HANDLERS[event]
  if not hs then return end
  for key, h in pairs(hs) do
    if h.once then hs[key] = nil end
    local ok, err = pcall(h.func, event, ...)
    if not ok then
      check(false, "handler '" .. tostring(key) .. "' for event '" .. event .. "' errored: " .. tostring(err))
    end
  end
end

function registerNamedEventHandler(user, name, event, func)
  HANDLERS[event] = HANDLERS[event] or {}
  HANDLERS[event][user .. "/" .. name] = { func = func }
  return true
end
local anon_id = 0
function registerAnonymousEventHandler(event, func, once)
  anon_id = anon_id + 1
  HANDLERS[event] = HANDLERS[event] or {}
  HANDLERS[event]["anon" .. anon_id] = { func = func, once = once }
  return anon_id
end

function registerNamedTimer(user, name, secs, func, repeating)
  TIMERS[name] = { user = user, secs = secs, func = func, repeating = repeating }
  return true
end
function deleteNamedTimer(user, name) TIMERS[name] = nil; return true end
function tempTimer(secs, func) local ok, e = pcall(func); if not ok then check(false, "tempTimer errored: " .. tostring(e)) end end

function enableTrigger(name) TRIGGER_STATE[name] = true end
function disableTrigger(name) TRIGGER_STATE[name] = false end
function killTrigger(id) end
function setTriggerStayOpen(name, n) end

function speedwalk(path, reverse, delay) table.insert(SPEEDWALKS, { path = path, reverse = reverse }) end

function getConnectionInfo() return "ckmud.example", 4000, connected end
function getConfig()
  return { enableGMCP = false, enableMNES = true, enableMSDP = true, enableMSP = false, enableMSSP = false, enableMTTS = true }
end
function setConfig(k, v) log("setConfig", k, tostring(v)) end
function reconnect() log("RECONNECT CALLED") end
function getEpoch() return fake_epoch end
function getMudletHomeDir() return "/fakeprofile" end
function installPackage(u) log("installPackage", u) end
function uninstallPackage(n) log("uninstallPackage", n) end
function createStopWatch(name, start) return name end
local watch_times = {}
function getStopWatchTime(name) return watch_times[name] or 0 end
function resetStopWatch(name) watch_times[name] = 0 end
function alert() end
function playSoundFile() end
function disconnect() end

msdp = {}

rex = {
  split = function(s, pattern)
    -- Only pattern used by the package is "(?<=]) " - split on "] " keeping the
    -- "]". Real rex.split returns an iterator, mirror that.
    assert(pattern == "(?<=]) ", "unexpected rex.split pattern: " .. tostring(pattern))
    local out = {}
    local pos = 1
    while true do
      local a = string.find(s, "] ", pos, true)
      if not a then
        if pos <= #s then table.insert(out, string.sub(s, pos)) end
        break
      end
      table.insert(out, string.sub(s, pos, a))
      pos = a + 2
    end
    local i = 0
    return function()
      i = i + 1
      return out[i]
    end
  end
}

-- Minimal Mudlet db API
db = {}
function db:create(dbname, schema)
  local out = {}
  for sheetname, fields in pairs(schema) do
    local sheet = { __rows = {} }
    for fname in pairs(fields) do
      if fname:sub(1, 1) ~= "_" then
        sheet[fname] = { sheet = sheet, field = fname }
      end
    end
    out[sheetname] = sheet
  end
  return out
end
function db:add(sheet, row)
  for i, r in ipairs(sheet.__rows) do
    if r.name == row.name then sheet.__rows[i] = row; return end
  end
  table.insert(sheet.__rows, row)
end
function db:eq(fieldref, value) return { op = "eq", field = fieldref.field, value = value } end
function db:not_in(fieldref, list) return { op = "not_in", field = fieldref.field, list = list } end
function db:fetch(sheet, crit)
  local res = {}
  for _, r in ipairs(sheet.__rows) do
    if crit == nil or (crit.op == "eq" and r[crit.field] == crit.value) then table.insert(res, r) end
  end
  return res
end
function db:delete(sheet, crit)
  local keep = {}
  for _, r in ipairs(sheet.__rows) do
    local del
    if crit == nil then del = true
    elseif crit.op == "eq" then del = r[crit.field] == crit.value
    elseif crit.op == "not_in" then del = not table.contains(crit.list, r[crit.field])
    end
    if not del then table.insert(keep, r) end
  end
  sheet.__rows = keep
end

-- yajl: package only round-trips values through it, identity works
yajl = {
  to_string = function(v) return v end,
  to_value = function(v) return v end,
}

---------------------------------------------------------------------------
-- Package loader (mirrors muddler+Mudlet: __PKGNAME__ substitution, require)
---------------------------------------------------------------------------
local PKG = "Autolearn"
local module_cache = {}

local function load_pkg_file(relpath, chunkname)
  local src = readfile(ROOT .. "/" .. relpath)
  assert(src, "cannot read " .. relpath)
  src = src:gsub("__PKGNAME__", PKG):gsub("__VERSION__", "26.07.26")
  local fn, err = load(src, "@" .. relpath)
  if not fn then error("SYNTAX " .. relpath .. ": " .. tostring(err)) end
  return fn
end

function require(name)
  if module_cache[name] then return module_cache[name] end
  local rel
  if name == PKG then rel = "resources/init.lua"
  elseif name == PKG .. ".console" then rel = "resources/console.lua"
  else error("unexpected require: " .. tostring(name)) end
  local fn = load_pkg_file(rel)
  local mod = fn()
  module_cache[name] = mod
  return mod
end

local function run_script(relpath)
  local ok, err = pcall(load_pkg_file(relpath))
  check(ok, "load script " .. relpath .. (ok and "" or (" -- " .. tostring(err))))
end

---------------------------------------------------------------------------
-- 1. Load all scripts in scripts.json order
---------------------------------------------------------------------------
realprint("=== PHASE: script load ===")
-- registration entry (inline in scripts.json)
local ok, err = pcall(function() require(PKG):register(PKG, "26.07.26") end)
check(ok, "registration script" .. (ok and "" or (" -- " .. tostring(err))))

-- The shared MSDP package is installed alongside this one (packages/MSDP); load it first
do
  local src = readfile(ROOT .. "/../../MSDP/src/MSDP.lua")
  assert(src, "cannot read packages/MSDP/src/MSDP.lua")
  local fn, err = load(src, "@MSDP.lua")
  local ok = fn and pcall(fn)
  check(ok == true, "load the shared MSDP package" .. (fn and "" or (" -- " .. tostring(err))))
end

for _, s in ipairs({
  "scripts/Utils.lua", "scripts/Core.lua", "scripts/Attacks.lua", "scripts/Damage.lua",
  "scripts/Fight.lua", "scripts/StateMachine.lua", "scripts/SendQueue.lua",
  "scripts/Skills.lua", "scripts/Modes.lua", "scripts/Racials.lua", "scripts/Learning.lua",
  "scripts/Event Handlers/MSDP.lua", "scripts/Event Handlers/Prompt_Events.lua",
  "scripts/Event Handlers/Connection_Events.lua",
}) do run_script(s) end

check(AL ~= nil, "AL global namespace exists")
check(AL and AL.API and AL.API.Learning and AL.API.Learning.toggle ~= nil, "AL.API.Learning:toggle exists")

---------------------------------------------------------------------------
-- 2. Connect: MSDP subscription
---------------------------------------------------------------------------
realprint("=== PHASE: connection ===")
raiseEvent("sysConnectionEvent")
check(#MSDP_SENT > 0 and MSDP_SENT[#MSDP_SENT][1] == "REPORT", "MSDP REPORT sent on sysConnectionEvent")
check(#LOG > 0, "log has entries")

-- 3. MSDP data arrives
realprint("=== PHASE: msdp feed ===")
local feed = {
  KI = "800", KI_MAX = "1000", GODKI = "500", GODKI_MAX = "500",
  FATIGUE = "900", FATIGUE_MAX = "1000", POWERLEVEL = "90000", POWERLEVEL_MAX = "100000",
  BASE_PL = "2000000", UBS = "50", LBS = "50", MAX_GRAVITY = "10", ROOM_GRAVITY = "1",
  CMD_STACK = "0", OPPONENT_NAME = "", OPPONENT_LEVEL = "0", OPPONENT_HEALTH = "0",
  OPPONENT_HEALTH_MAX = "0", UPDATE_EPOCH = tostring(fake_epoch),
  STR = "50", INT = "60", WIS = "70", SPD = "40", CON = "30",
  STR_BASE = "45", INT_BASE = "55", WIS_BASE = "65", SPD_BASE = "35", CON_BASE = "25",
  DAMROLL = "10", HITROLL = "10", ZENNI = "1000",
}
for k, v in pairs(feed) do
  msdp[k] = v
  raiseEvent("msdp." .. k)
end
check(AL.Player.Ki == 800, "AL.Player.Ki populated from MSDP (got " .. tostring(AL.Player.Ki) .. ")")
check(AL.Player.MaxGravity == 10, "AL.Player.MaxGravity populated")
check(AL.cmd_stack == 0, "AL.cmd_stack populated")
check(AL.Target.name == "", "AL.Target.name populated")
check(AL.Player.Stats.INT == 60, "AL.Player.Stats.INT populated")

---------------------------------------------------------------------------
-- 4. Score output: name + race
---------------------------------------------------------------------------
realprint("=== PHASE: score parse ===")
multimatches = { {}, { "Score Information for: Vorrac", "  Vorrac " } }
local score_script = load("local name = string.trim(multimatches[2][2])\nAL.API:setName(name)\n")
ok, err = pcall(score_script); check(ok, "Score Inject script" .. (ok and "" or (" -- " .. tostring(err))))
multimatches = { {}, { "Race: Human", " Human " } }
local race_script = load("local race = string.trim(multimatches[2][2])\nAL.API:setRace(race)\n")
ok, err = pcall(race_script); check(ok, "Score Race script" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API:getRace() == "Human", "race parsed as Human")
check(AL.API:getName() == "Vorrac", "name parsed")

---------------------------------------------------------------------------
-- 5. learn output scraping
---------------------------------------------------------------------------
realprint("=== PHASE: skill scrape ===")
local scrape_parent = load("AL.API.Skills.clear()")
ok, err = pcall(scrape_parent); check(ok, "Learn Scrape parent script" .. (ok and "" or (" -- " .. tostring(err))))

local section_fn = load_pkg_file("triggers/Skills/Skill_Sections.lua")
local scrape_fn = load_pkg_file("triggers/Skills/scrape_skill.lua")

local function scrape_section(name, rows)
  matches = { name .. " Attacks:", name }
  ok, err = pcall(section_fn); check(ok, "Skill_Sections " .. name .. (ok and "" or (" -- " .. tostring(err))))
  for _, row in ipairs(rows) do
    -- Mudlet matchall layout: {full1, g1, g2, full2, g1, g2}
    if row[3] then
      matches = { row[1] .. " " .. row[2], row[1], row[2], row[3] .. " " .. row[4], row[3], row[4] }
    else
      matches = { row[1] .. " " .. row[2], row[1], row[2] }
    end
    ok, err = pcall(scrape_fn); check(ok, "scrape_skill " .. tostring(row[1]) .. (ok and "" or (" -- " .. tostring(err))))
  end
end

scrape_section("Physical", { { "punch", "75%", "kick", "Mastered" }, { "roundhouse", "20%" } })
scrape_section("Ki", { { "kamehameha", "50%", "kiblast", "Mastered" } })
scrape_section("Focus", { { "heal", "20%", "meditate", "Mastered" } })

local close_fn = load("setTriggerStayOpen(\"Learn Scrape\", 0) AL.Player.Skills.section = nil")
ok, err = pcall(close_fn); check(ok, "close Learn scrape" .. (ok and "" or (" -- " .. tostring(err))))

check(AL.Player.Skills.Learned["punch"] == true, "punch learned")
check(AL.Player.Skills.Mastered["kick"] == true, "kick mastered")
check(AL.Player.Skills.Level["punch"] == 75, "punch level 75")
check(AL.Player.Skills.Learned["kame"] == true, "kamehameha translated to kame and learned")
check(table.contains(AL.Player.Skills.Sections.Ki, "kame"), "kame in Ki section")
check(table.contains(AL.Player.Skills.Sections.Focus, "heal"), "heal in Focus section")

---------------------------------------------------------------------------
-- 6. Prompt fires
---------------------------------------------------------------------------
realprint("=== PHASE: prompt ===")
multimatches = { {}, { ["PL"] = "90,000", ["Forms"] = "[FLY]" } }
local prompt_fn = load_pkg_file("triggers/Prompt.lua")
ok, err = pcall(prompt_fn); check(ok, "Prompt trigger script" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.Toggles.firstprompt == true, "firstprompt set after prompt")
check(AL.Player.Status["FLY"] == true, "FLY status parsed")
check(AL.API:is_connected() == true, "API:is_connected() true after prompt")

---------------------------------------------------------------------------
-- 7. Toggle autolearn on
---------------------------------------------------------------------------
realprint("=== PHASE: autolearn toggle ===")
SENT = {}
matches = { "autolearn troll n;n;e", "troll", "n;n;e" }
local alias_fn = load("AL.API.Learning:toggle(matches[2], matches[3])")
ok, err = pcall(alias_fn); check(ok, "autolearn alias" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API.Mode:is(AL.API.Mode.Learning), "Mode is Learning after toggle")
check(table.contains(SENT, "learn"), "'learn' sent on enter")
check(TIMERS["AL:Learning"] ~= nil, "learning timer registered")
check(TRIGGER_STATE["autolearn no target"] == true, "no-target trigger enabled")

-- "Maybe you should land first!" while the bot runs: land
SENT = {}
local land_fn = load("AL.API.Learning:land()")       -- the 'autolearn land' trigger's script
ok, err = pcall(land_fn); check(ok, "land trigger script" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "land"), "lands when told to while autolearn runs")

---------------------------------------------------------------------------
-- 8. Bot tick: should send a skill at the target
---------------------------------------------------------------------------
realprint("=== PHASE: bot ticks ===")
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "do_learning tick 1" .. (ok and "" or (" -- " .. tostring(err))))
local attacked = false
for _, c in ipairs(SENT) do
  if c:find("troll", 1, true) or c:find("focus", 1, true) then attacked = true end
end
check(attacked, "bot sent a skill/attack on tick (sent: " .. table.concat(SENT, " | ") .. ")")

-- another prompt between ticks (the event loop keeps running)
multimatches = { {}, { ["PL"] = "90,000", ["Forms"] = "" } }
ok, err = pcall(prompt_fn); check(ok, "Prompt during learning" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 8b. Costs from the attack table: an expensive skill waits while cheaper ones train
---------------------------------------------------------------------------
realprint("=== PHASE: affordable skills first ===")
do
  local P = AL.Player
  P.Skills.Learned["finalk"] = true; P.Skills.Level["finalk"] = 10
  table.insert(P.Skills.Sections.Ki, 1, "finalk")          -- finalk costs 1000 ki, kame 20
  P.Ki, P.MaxKi, P.Fatigue, P.MaxFatigue = 500, 1000, 1000, 1000
  SENT = {}
  ok, err = pcall(TIMERS["AL:Learning"].func)
  check(ok, "tick with low ki" .. (ok and "" or (" -- " .. tostring(err))))
  check(table.contains(AL.API.Learning.to_learn.energy, "finalk"), "finalk is waiting to be trained")
  check(table.contains(SENT, "kame troll") and not table.contains(SENT, "finalk troll"),
    "not enough ki for finalk: kame trains instead (sent: " .. table.concat(SENT, " | ") .. ")")
  P.Ki = 1
  SENT = {}
  ok, err = pcall(TIMERS["AL:Learning"].func)
  check(ok, "tick with no ki" .. (ok and "" or (" -- " .. tostring(err))))
  check(table.contains(SENT, "roundhouse troll") or table.contains(SENT, "punch troll"), "out of ki: a fatigue skill trains (sent: " .. table.concat(SENT, " | ") .. ")")
  P.Ki = 1000
  SENT = {}
  ok, err = pcall(TIMERS["AL:Learning"].func)
  check(table.contains(SENT, AL.API.Learning.to_learn.energy[1] .. " troll"), "enough ki again: the first energy skill trains, whichever it is")
  P.Skills.Mastered["finalk"] = true; P.Skills.Level["finalk"] = 100
end

---------------------------------------------------------------------------
-- 9. Everything mastered + tired -> rest cycle
---------------------------------------------------------------------------
realprint("=== PHASE: rest cycle ===")
for _, sk in ipairs({ "punch", "kame", "heal", "roundhouse" }) do
  AL.Player.Skills.Mastered[sk] = true
  AL.Player.Skills.Level[sk] = 100
end
AL.Player.UBS = 100
AL.Player.LBS = 100
-- Nothing affordable: too tired to use even the newly learnable skills
AL.Player.Ki = 1
AL.Player.Fatigue = 1
SENT = {}
SPEEDWALKS = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "do_learning tick 2 (rest)" .. (ok and "" or (" -- " .. tostring(err))))
check(#SPEEDWALKS == 1, "speedwalked to rest spot")
raiseEvent("sysSpeedwalkFinished")
check(table.contains(SENT, "sleep"), "sent sleep after speedwalk")
check(AL.API.State:is(AL.API.State.REST), "state is REST")

-- fully rested -> wake up and walk back
AL.Player.Ki = 1000; AL.Player.Pl = 100000; AL.Player.Fatigue = 1000; AL.Player.GK = 500
AL.Player.MaxKi = 1000; AL.Player.MaxPl = 100000; AL.Player.MaxFatigue = 1000; AL.Player.MaxGK = 500
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "do_learning tick 3 (wake)" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "wake"), "sent wake when rested")
raiseEvent("sysSpeedwalkFinished")
check(AL.API.State:is(AL.API.State.NORMAL), "state back to NORMAL after return walk")

---------------------------------------------------------------------------
-- 9b. "You lack sufficient god ki to use that technique!": set that skill aside,
--     train the ones using ki/fatigue first, rest only when nothing else can be done
---------------------------------------------------------------------------
realprint("=== PHASE: out of god ki ===")
do
  local L = AL.API.Learning
  local god_ki_fn = load("AL.API.Learning:out_of_god_ki()")   -- the trigger's script
  -- Something left to train for this phase: two attacks, both affordable
  for _, sk in ipairs({ "finger", "dsphere" }) do
    AL.Player.Skills.Learned[sk] = true
    AL.Player.Skills.Mastered[sk] = nil
  end
  AL.Player.GK = 50                                  -- low god ki, everything else full

  SENT = {}
  pcall(TIMERS["AL:Learning"].func)
  local first = SENT[1]
  check(first ~= nil, "tick trains a skill (sent: " .. table.concat(SENT, " | ") .. ")")
  ok, err = pcall(god_ki_fn); check(ok, "out-of-god-ki trigger script" .. (ok and "" or (" -- " .. tostring(err))))
  local skill = first and first:match("^(%S+)")
  check(skill and L:gk_blocked_skill(skill), "the skill that hit the god ki wall is set aside: " .. tostring(skill))

  SENT, SPEEDWALKS = {}, {}
  pcall(TIMERS["AL:Learning"].func)
  check(#SPEEDWALKS == 0 and SENT[1] ~= nil and not SENT[1]:find(skill, 1, true),
        "keeps training another skill instead of resting (sent: " .. table.concat(SENT, " | ") .. ")")

  -- Nothing else affordable: now it rests (god ki isn't full, so it isn't "rested")
  AL.Player.Ki, AL.Player.Fatigue = 1, 1
  SENT, SPEEDWALKS = {}, {}
  pcall(TIMERS["AL:Learning"].func)
  check(#SPEEDWALKS == 1, "rests once nothing else can be trained")
  raiseEvent("sysSpeedwalkFinished")
  check(AL.API.State:is(AL.API.State.REST), "sleeping")
  AL.Player.Ki, AL.Player.Fatigue = AL.Player.MaxKi, AL.Player.MaxFatigue
  SENT = {}
  pcall(TIMERS["AL:Learning"].func)
  check(not table.contains(SENT, "wake"), "stays asleep while god ki isn't full")
  AL.Player.GK = AL.Player.MaxGK
  SENT = {}
  pcall(TIMERS["AL:Learning"].func)
  check(table.contains(SENT, "wake"), "wakes once god ki is full")
  raiseEvent("sysSpeedwalkFinished")

  -- Back at the target with full god ki: the set-aside skill is tried again
  SENT = {}
  pcall(TIMERS["AL:Learning"].func)
  check(not L:gk_blocked_skill(skill), "set-aside skill released once god ki is full")
  check(SENT[1] ~= nil and SENT[1]:find(skill, 1, true), "and it's trained again (sent: " .. table.concat(SENT, " | ") .. ")")
  for _, sk in ipairs({ "finger", "dsphere" }) do AL.Player.Skills.Mastered[sk] = true end
end

---------------------------------------------------------------------------
-- 10. no-target trigger + toggle off
---------------------------------------------------------------------------
realprint("=== PHASE: no-target + toggle off ===")
ok = pcall(function() AL.ck = nil end)
local set_const = require(PKG)
set_const:set_constant("learning.return_to_target", "crecall;n;n")
SENT = {}
multimatches = { {}, { "learn troll who?", "learn troll" } }
local nt_fn = load("AL.API.Learning:find_target(multimatches[2][2])")
ok, err = pcall(nt_fn); check(ok, "no-target trigger script" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "crecall"), "return_to_target commands sent (sent: " .. table.concat(SENT, " | ") .. ")")

matches = { "autolearn", nil, nil }
ok, err = pcall(alias_fn); check(ok, "autolearn toggle off" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API.Mode:is(AL.API.Mode.Interactive), "Mode back to Interactive")
check(TIMERS["AL:Learning"] == nil, "learning timer deleted")
SENT = {}
pcall(land_fn)
check(not table.contains(SENT, "land"), "doesn't land when autolearn is off (your own commands)")
pcall(load("AL.API.Learning:out_of_god_ki()"))
check(not next(AL.API.Learning.gk_blocked), "the god ki message is ignored when autolearn is off")

---------------------------------------------------------------------------
-- 11. Ultra training gate: GK >= 500 * (100 - level) / 100 + 5 (nil level -> 1)
---------------------------------------------------------------------------
realprint("=== PHASE: ultra_ok formula ===")
AL.Player.Skills.Learned["ultra instinct"] = true
AL.Player.Skills.Level["ultra instinct"] = 50
matches = { "autolearn troll n;n;e", "troll", "n;n;e" }
ok, err = pcall(alias_fn); check(ok, "autolearn toggle for ultra phase" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API.Mode:is(AL.API.Mode.Learning), "Learning mode on for ultra phase")

local function sent_ultra(name)
  for _, c in ipairs(SENT) do
    if c:find(name, 1, true) then return true end
  end
  return false
end

-- level 50: needs GK >= 500 * 50 / 100 + 5 = 255
AL.Player.GK = 254
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra below threshold" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent_ultra("ultra instinct"), "no ultra focus at GK 254 for level 50")

AL.Player.GK = 255
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra at threshold" .. (ok and "" or (" -- " .. tostring(err))))
check(sent_ultra("ultra instinct"), "ultra focus sent at GK 255 for level 50 (sent: " .. table.concat(SENT, " | ") .. ")")
check(table.contains(SENT, "urevert"), "urevert sent with ultra focus")

-- level 100 (not yet Mastered): needs only GK >= 5
AL.Player.Skills.Level["ultra instinct"] = 100
AL.Player.GK = 4
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra level 100 below" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent_ultra("ultra instinct"), "no ultra focus at GK 4 for level 100")

AL.Player.GK = 5
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra level 100 at threshold" .. (ok and "" or (" -- " .. tostring(err))))
check(sent_ultra("ultra instinct"), "ultra focus sent at GK 5 for level 100")

-- freshly learned ultra with no scraped level yet: nil level treated as 1 -> 500
AL.Player.Skills.Mastered["ultra instinct"] = true
AL.Player.Skills.Learned["ultra ego"] = true
AL.Player.GK = 499
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra nil level below" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent_ultra("ultra ego"), "no ultra focus at GK 499 for nil level")

AL.Player.GK = 500
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick ultra nil level at threshold" .. (ok and "" or (" -- " .. tostring(err))))
check(sent_ultra("ultra ego"), "ultra focus sent at GK 500 for nil level")

matches = { "autolearn", nil, nil }
ok, err = pcall(alias_fn); check(ok, "toggle off after ultra phase" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 12. Instant/portal training only teleports away with a configured return
---------------------------------------------------------------------------
realprint("=== PHASE: instant transmission gating ===")
-- Quiet every earlier branch: master all remaining skills, keep body maxed
for _, sk in ipairs({ "ultra ego", "superk", "machpunch", "machkick" }) do
  AL.Player.Skills.Learned[sk] = true
  AL.Player.Skills.Mastered[sk] = true
  AL.Player.Skills.Level[sk] = 100
end
AL.Player.Skills.Learned["instant"] = true -- learned but NOT mastered
AL.Player.GK = 500
AL.Player.Ki = 1000

local ck_mod = require(PKG)
ck_mod:set_constant("learning.return_to_target", "")

local function sent_instant()
  for _, c in ipairs(SENT) do
    if c:find("instant", 1, true) then return true end
  end
  return false
end
local function warnings_logged()
  local n = 0
  for _, l in ipairs(LOG) do
    if l:find("Skipping portal/instant", 1, true) then n = n + 1 end
  end
  return n
end

matches = { "autolearn troll n;n;e", "troll", "n;n;e" }
ok, err = pcall(alias_fn); check(ok, "autolearn toggle for instant phase" .. (ok and "" or (" -- " .. tostring(err))))
check(TRIGGER_STATE["autolearn no target"] == true, "no-target trigger armed even without return path")

SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick instant unconfigured" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent_instant(), "no instant teleport without return path (sent: " .. table.concat(SENT, " | ") .. ")")
check(warnings_logged() == 1, "skip warning printed")

SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick instant unconfigured again" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent_instant(), "still no instant teleport without return path")
check(warnings_logged() == 1, "skip warning printed only once")

-- configure the way back mid-session -> training may proceed
ck_mod:set_constant("learning.return_to_target", "crecall;n;n")
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick instant configured" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "focus 'instant' king kai"), "instant training fires with return path set")

-- after teleporting, a broke bot must walk home BEFORE trying to rest
AL.Player.Ki = 400 -- too low for another instant cast, and not rested
SENT = {}
SPEEDWALKS = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick after teleport, broke" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "crecall"), "returns home before resting (sent: " .. table.concat(SENT, " | ") .. ")")
check(not table.contains(SENT, "sleep") and #SPEEDWALKS == 0, "no rest attempt from king kai")
check(AL.API.State:is(AL.API.State.NORMAL), "state stays NORMAL while walking home")

-- next tick: back at the target, resting may proceed (speedwalk fallback here)
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick rest after returning" .. (ok and "" or (" -- " .. tostring(err))))
check(not table.contains(SENT, "crecall"), "return path not repeated once home")
check(#SPEEDWALKS == 1, "rest speedwalk only after returning home")
raiseEvent("sysSpeedwalkFinished")
check(AL.API.State:is(AL.API.State.REST), "resting after the return trip")

-- recover for the remaining checks
AL.Player.Ki = 1000
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick wake after teleport rest" .. (ok and "" or (" -- " .. tostring(err))))
raiseEvent("sysSpeedwalkFinished")
check(AL.API.State:is(AL.API.State.NORMAL), "back to NORMAL after teleport rest cycle")

-- and the stranded recovery still works: '<target> who?' walks back
SENT = {}
multimatches = { {}, { "kame troll who?", "kame troll" } }
ok, err = pcall(nt_fn); check(ok, "no-target trigger after teleport" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "crecall"), "return path sent after failed attack (sent: " .. table.concat(SENT, " | ") .. ")")

matches = { "autolearn", nil, nil }
ok, err = pcall(alias_fn); check(ok, "toggle off after instant phase" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 13. Recall-based rest: recall_isolation + return_to_target, no speedwalk
---------------------------------------------------------------------------
realprint("=== PHASE: recall rest ===")
AL.Player.Skills.Mastered["instant"] = true
AL.Player.Skills.Level["instant"] = 100
-- mastering instant makes warp learnable (via superk); mark it learned so
-- the bot has genuinely nothing left to do and must rest
AL.Player.Skills.Learned["warp"] = true
AL.Player.Skills.Mastered["warp"] = true
local ck_mod2 = require(PKG)
ck_mod2:set_constant("learning.recall_isolation", "")
ck_mod2:set_constant("learning.return_to_target", "")

-- organic with no speedwalk and no recall config: refused
matches = { "autolearn troll", "troll", nil }
ok, err = pcall(alias_fn); check(ok, "toggle without path, unconfigured" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API.Mode:is(AL.API.Mode.Interactive), "refused without speedwalk or recall config")

-- both constants set: the speedwalk argument becomes optional
ck_mod2:set_constant("learning.recall_isolation", "recall;s;w")
ck_mod2:set_constant("learning.return_to_target", "crecall;n;n")
ok, err = pcall(alias_fn); check(ok, "toggle without path, configured" .. (ok and "" or (" -- " .. tostring(err))))
check(AL.API.Mode:is(AL.API.Mode.Learning), "learning mode on without speedwalk argument")

-- nothing left to train and not rested -> recall to isolation and sleep
AL.Player.Ki = 500
SENT = {}
SPEEDWALKS = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick recall rest" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "recall") and table.contains(SENT, "w") and table.contains(SENT, "sleep"),
  "recalled to isolation and slept (sent: " .. table.concat(SENT, " | ") .. ")")
check(#SPEEDWALKS == 0, "no speedwalk used for recall rest")
check(AL.API.State:is(AL.API.State.REST), "state is REST after recall rest")

-- rested -> wake and walk back via return_to_target
AL.Player.Ki = 1000
SENT = {}
ok, err = pcall(TIMERS["AL:Learning"].func)
check(ok, "tick recall wake" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "wake") and table.contains(SENT, "crecall"),
  "woke and returned via return_to_target (sent: " .. table.concat(SENT, " | ") .. ")")
check(AL.API.State:is(AL.API.State.NORMAL), "state NORMAL after recall wake")

matches = { "autolearn", nil, nil }
ok, err = pcall(alias_fn); check(ok, "toggle off after recall rest phase" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 14. Config aliases
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Tuffle racial skills: Distortion Ray and Quantum Cannon
---------------------------------------------------------------------------
realprint("=== PHASE: new melee skills ===")
do
  local function logged(text)
    for _, l in ipairs(LOG) do if l:find(text, 1, true) then return true end end
    return false
  end
  local X, tc = AL.API.Attacks.Extras, AL.Player.Attacks["thunderclap"]
  check(tc ~= nil and tc[1] == 4 and tc[2] == 0.95 and tc[3] == true and tc[4] == 1,
        "thunderclap: 4 fatigue, 95% damage on UBS, 1 round cooldown")
  check(tc and tc[6][X.daze] and tc[6][X.piercing] and tc[6][X.piercing_major],
        "thunderclap dazes and bypasses armor 20/25/30%")
  LOG = {}
  AL.API:can_use_melee_attack("thunderclap")
  check(not logged("Unknown Melee"), "no more 'Unknown Melee thunderclap' error")

  local sdf = AL.Player.Attacks["superdragonfist"]
  check(sdf ~= nil and sdf[1] == 8 and sdf[2] == 0.80 and sdf[3] == true and sdf[4] == 2 and sdf[5] == 6,
        "superdragonfist: 8 fatigue, 80% damage on UBS, 2 rounds, up to 6 hits")
  check(sdf and sdf[6][X.piercing] and sdf[6][X.piercing_major], "superdragonfist bypasses armor 30%")
  check(AL.API.Skills:translate("super dragon fist") == "superdragonfist", "'super dragon fist' from learn is superdragonfist")
  LOG = {}
  AL.API:can_use_melee_attack(AL.API.Skills:translate("super dragon fist"))
  check(not logged("Unknown Melee"), "no more 'Unknown Melee super dragon fist' error")

  -- A skill the MUD adds later: skipped (once warned), the rest still gets trained
  LOG = {}
  local L = AL.API.Learning
  local list = L:known_attacks({ "skillfromthefuture", "thunderclap", "kick" })
  check(#list == 2 and list[1] == "thunderclap" and list[2] == "kick", "unknown attacks are left out of training")
  check(logged("Skipping skillfromthefuture"), "with a warning naming the skill")
  LOG = {}
  L:known_attacks({ "skillfromthefuture" })
  check(not logged("Skipping skillfromthefuture"), "warned only once")
end

realprint("=== PHASE: tuffle racials ===")
do
  local AT = AL.Player.Attacks
  check(AT["distort"] ~= nil and AT["distort"][6][AL.API.Attacks.Extras.daze] == true, "Distortion Ray attack exists and dazes")
  check(AT["quantum"] ~= nil and AT["quantum"][2] == 3.5, "Quantum Cannon attack exists")
  local Sk = AL.API.Skills
  check(Sk:translate("distortion ray") == "distort", "'distortion ray' translates to distort")
  check(Sk:translate("quantum cannon") == "quantum", "'quantum cannon' translates to quantum")
  check(Sk:translate("bulletstorm") == "bullet", "'bulletstorm' translates to bullet")

  -- Save what the earlier phases set, then try both races
  local race, M, L = AL.API:getRace(), AL.Player.Skills.Mastered, AL.Player.Skills.Learned
  local function offers(cmd)
    for _, c in ipairs(Sk:learnable()) do if c == cmd then return true end end
    return false
  end
  AL.Player.Skills.Mastered = { distort = true, bullet = true }
  AL.Player.Skills.Learned = { scatter = true }
  AL.API:setRace("Tuffle")
  check(offers("distort"), "a Tuffle with Distortion Ray and Bulletstorm mastered is offered Quantum Cannon")
  AL.API:setRace("Human")
  check(not offers("distort"), "other races aren't")
  AL.API:setRace("Tuffle")
  AL.Player.Skills.Learned["quantum"] = true
  check(not offers("distort"), "not once Quantum Cannon is learned")
  AL.Player.Skills.Mastered, AL.Player.Skills.Learned = M, L
  AL.API:setRace(race)
end

realprint("=== PHASE: config aliases ===")
matches = { "AL features" }
ok, err = pcall(load_pkg_file("aliases/AL_feature.lua")); check(ok, "AL features alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "AL feature learning.use_zeta on", "learning.use_zeta", "on" }
ok, err = pcall(load_pkg_file("aliases/AL_feature_toggle.lua")); check(ok, "AL feature toggle alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):feature("learning.use_zeta") == true, "feature persisted to on")
matches = { "AL constants", nil }
ok, err = pcall(load_pkg_file("aliases/AL_constant.lua")); check(ok, "AL constants alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { 'AL constant learning.recall_isolation="recall;s"', "learning.recall_isolation", '"recall;s"' }
ok, err = pcall(load_pkg_file("aliases/AL_constant_set.lua")); check(ok, "AL constant set alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):constant("learning.recall_isolation") == "recall;s", "constant persisted")
matches = { "AL" }
ok, err = pcall(load_pkg_file("aliases/AL_Help.lua")); check(ok, "AL help alias" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
realprint("")
realprint(("=== RESULT: %d passed, %d failed ==="):format(passes, #failures))
for _, m in ipairs(failures) do realprint("  FAILED: " .. m) end
if #failures > 0 then error("harness failures", 0) end
