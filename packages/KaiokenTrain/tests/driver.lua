-- Mudlet environment simulator + KaiokenTrain package smoke test.
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
TEMP_TRIGGERS = {}
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

function tempRegexTrigger(pattern, func, count)
  table.insert(TEMP_TRIGGERS, { pattern = pattern, func = func, count = count })
  return #TEMP_TRIGGERS
end
function gagLine() log("[gag]") end
function killTrigger(id) end
function enableTrigger(name) end
function disableTrigger(name) end
function setTriggerStayOpen(name, n) end

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
WATCH_TIMES = {}
local watch_times = WATCH_TIMES
function getStopWatchTime(name) return watch_times[name] or 0 end
function resetStopWatch(name) watch_times[name] = 0 end
function alert() end
function disconnect() end

msdp = {}

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

yajl = {
  to_string = function(v) return v end,
  to_value = function(v) return v end,
}

---------------------------------------------------------------------------
-- Package loader
---------------------------------------------------------------------------
local PKG = "KaiokenTrain"
local module_cache = {}

local function load_pkg_file(relpath)
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
  local mod = load_pkg_file(rel)()
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
  "scripts/Core.lua", "scripts/StateMachine.lua", "scripts/Modes.lua", "scripts/Kaioken.lua",
  "scripts/Event Handlers/MSDP.lua", "scripts/Event Handlers/Prompt_Events.lua",
  "scripts/Event Handlers/Connection_Events.lua",
}) do run_script(s) end

check(KT ~= nil, "KT global namespace exists")
check(KT and KT.API and KT.API.Kaioken and KT.API.Kaioken.toggle ~= nil, "KT.API.Kaioken:toggle exists")

---------------------------------------------------------------------------
-- 2. Connect + MSDP feed
---------------------------------------------------------------------------
realprint("=== PHASE: connection + msdp ===")
raiseEvent("sysConnectionEvent")
check(#MSDP_SENT > 0 and MSDP_SENT[#MSDP_SENT][1] == "REPORT", "MSDP REPORT sent on sysConnectionEvent")

local feed = {
  KI = "1000", KI_MAX = "1000", GODKI = "500", GODKI_MAX = "500",
  FATIGUE = "900", FATIGUE_MAX = "1000", POWERLEVEL = "100000", POWERLEVEL_MAX = "100000",
  THIRST = "80", CMD_STACK = "0", UPDATE_EPOCH = tostring(fake_epoch),
}
for k, v in pairs(feed) do
  msdp[k] = v
  raiseEvent("msdp." .. k)
end
check(KT.Player.Fatigue == 900, "KT.Player.Fatigue populated")
check(KT.Player.Thirst == 80, "KT.Player.Thirst populated")

---------------------------------------------------------------------------
-- 3. Prompt + kaioken parsing
---------------------------------------------------------------------------
realprint("=== PHASE: prompt parsing ===")
local prompt_fn = load_pkg_file("triggers/Prompt.lua")
local pkaio_fn = load_pkg_file("triggers/Prompt_Kaioken.lua")

multimatches = { {}, { ["CURR"] = "5", ["MAX"] = "10" } }
ok, err = pcall(pkaio_fn); check(ok, "Prompt Kaioken script" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.Player.Kaioken == 5 and KT.Player.MKaioken == 10, "kaioken CURR/MAX parsed")
check(KT.PromptFlags.Kaioken == true, "PromptFlags.Kaioken set")

ok, err = pcall(prompt_fn); check(ok, "Prompt trigger script" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.Toggles.firstprompt == true, "firstprompt set after prompt")
check(KT.Player.Kaioken == 5, "kaioken value survives prompt with flag set")

-- next prompt without the kaioken segment: value resets to 0
ok, err = pcall(prompt_fn); check(ok, "Prompt without kaioken segment" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.Player.Kaioken == 0, "kaioken zeroed when prompt lacks the segment")

-- status output parser
multimatches = { {}, { "You have mastered kaioken x10.", "10" } }
local status_fn = load("KT.Player.MKaioken = tonumber(multimatches[2][2])")
ok, err = pcall(status_fn); check(ok, "Status mastered kaioken script" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.Player.MKaioken == 10, "MKaioken from status output")

---------------------------------------------------------------------------
-- 4. Toggle on
---------------------------------------------------------------------------
realprint("=== PHASE: toggle on ===")
SENT = {}
-- enabling forgets the old mastery and asks 'status' again: before any tick, nothing is
-- trained, then the status reply (simulated by restoring the value) brings it back
local raw_toggle = load("KT.API.Kaioken:toggle()")
local toggle_fn = function()
  local m = KT.Player.MKaioken
  raw_toggle()
  if KT.API.Mode:is(KT.API.Mode.Kaioken) then
    check(KT.Player.MKaioken == nil and table.contains(SENT, "status"), "enable re-reads mastery with 'status'")
    KT.Player.MKaioken = m
  end
end
ok, err = pcall(toggle_fn); check(ok, "kaioken train alias" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken getmax"), "'kaioken getmax' sent")
check(#TEMP_TRIGGERS == 2, "getmax temp trigger installed (after the prompt watch line counter)")
check(KT.API.Mode:is(KT.API.Mode.Kaioken), "Mode is Kaioken")
check(KT.API.Mode:toString() == "Kaioken", "Mode:toString reports Kaioken (CK bug fixed)")
check(TIMERS["KT:Kaioken"] ~= nil, "kaioken timer registered")

-- server replies with the syntax line -> temp trigger captures max
matches = { "Syntax: Kaioken 1-120", "120" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax trigger callback" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.API.Kaioken.max == 120, "kaio.max captured as 120")

---------------------------------------------------------------------------
-- 5. Training ticks
---------------------------------------------------------------------------
local function tick()
  local t = TIMERS["KT:Kaioken"]
  if not t then return false, "KT:Kaioken timer no longer exists" end
  return pcall(t.func)
end

realprint("=== PHASE: training ticks ===")
KT.Player.Kaioken = 5
SENT = {}
ok, err = tick()
check(ok, "tick raise" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 21"), "raised kaioken toward MKaioken+11 (sent: " .. table.concat(SENT, " | ") .. ")")

-- at target, thirsty -> drink
KT.Player.Kaioken = 21
KT.Player.Thirst = 20
SENT = {}
ok, err = tick()
check(ok, "tick drink" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "drink tears"), "drank the default (tears) when thirsty")

-- the drink command is a constant
require(PKG):set_constant("kaioken.drink_cmd", "drink flask")
SENT = {}
ok, err = tick(); check(ok, "tick drink custom" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "drink flask"), "drank the configured command")
require(PKG):set_constant("kaioken.drink_cmd", "drink tears")

-- exhausted -> drop kaioken and sleep
KT.Player.Thirst = 80
KT.Player.Fatigue = 100
SENT = {}
ok, err = tick()
check(ok, "tick rest" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken") and table.contains(SENT, "sleep"), "dropped kaioken and slept")
check(SENT[#SENT] == "sleep" and SENT[#SENT - 1] == "land", "landed right before sleeping")
check(KT.API.State:is(KT.API.State.REST), "state is REST")

-- rested -> wake
KT.Player.Fatigue = 1000
KT.Player.Ki = 1000
KT.Player.Pl = 100000
KT.Player.MaxPl = 100000
KT.Player.GK = 500
SENT = {}
ok, err = tick()
check(ok, "tick wake" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "wake"), "woke when rested")
check(KT.API.State:is(KT.API.State.NORMAL), "state back to NORMAL")

-- mastered -> re-verify max against the server, then finish and exit mode
KT.Player.MKaioken = 112
SENT = {}
ok, err = tick()
check(ok, "tick verify" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken getmax"), "re-checks max before declaring mastery")
check(KT.API.Mode:is(KT.API.Mode.Kaioken), "still training while max unverified")
-- server confirms the ceiling did not grow
matches = { "Syntax: Kaioken 1-120", "120" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax confirm callback" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
ok, err = tick()
check(ok, "tick finish" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 112"), "set kaioken to mastered goal")
check(KT.API.Mode:is(KT.API.Mode.Interactive), "Mode back to Interactive when done")
check(TIMERS["KT:Kaioken"] == nil, "kaioken timer deleted on finish")

---------------------------------------------------------------------------
-- 6. Stale max: the ceiling grows while training (stops-at-32 bug)
---------------------------------------------------------------------------
realprint("=== PHASE: stale max regrowth ===")
KT.Player.MKaioken = 24
KT.Player.Kaioken = 24
KT.Player.Thirst = 80
KT.Player.Fatigue = 1000
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "toggle on again" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.API.Mode:is(KT.API.Mode.Kaioken), "training mode re-entered")
-- server currently caps kaioken at 40
matches = { "Syntax: Kaioken 1-40", "40" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax 40 callback" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.API.Kaioken.max == 40, "kaio.max captured as 40")

SENT = {}
ok, err = tick()
check(ok, "tick raise toward 35" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 35"), "raised kaioken to MKaioken+11 under cap 40")

-- mastery reaches the stale goal (40-8=32) but the ceiling has grown since
KT.Player.Kaioken = 33
KT.Player.MKaioken = 32
SENT = {}
ok, err = tick()
check(ok, "tick at stale goal" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken getmax"), "re-checks max at goal instead of stopping at 32")
check(KT.API.Mode:is(KT.API.Mode.Kaioken), "does NOT stop training at 32")
check(TIMERS["KT:Kaioken"] ~= nil, "timer still running at stale goal")

-- server now reports a higher ceiling
matches = { "Syntax: Kaioken 1-48", "48" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax 48 callback" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.API.Kaioken.max == 48, "kaio.max refreshed to 48")

SENT = {}
ok, err = tick()
check(ok, "tick continue past 32" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 43"), "training continues toward the new ceiling (sent: " .. table.concat(SENT, " | ") .. ")")

-- mastery reaches the new goal (48-8=40) and this time the ceiling is confirmed
KT.Player.Kaioken = 41
KT.Player.MKaioken = 40
SENT = {}
ok, err = tick()
check(ok, "tick verify at 40" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken getmax"), "re-checks max at new goal")
matches = { "Syntax: Kaioken 1-48", "48" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax confirm 48 callback" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
ok, err = tick()
check(ok, "tick finish at 40" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 40"), "finishes at the confirmed goal")
check(KT.API.Mode:is(KT.API.Mode.Interactive), "Mode Interactive after confirmed mastery")
check(TIMERS["KT:Kaioken"] == nil, "timer deleted after confirmed mastery")

---------------------------------------------------------------------------
-- 7. Toggling again when already maxed (verified live, not from stale state)
---------------------------------------------------------------------------
realprint("=== PHASE: already maxed ===")
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "toggle when maxed" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken getmax"), "asks the server for max on enable")
matches = { "Syntax: Kaioken 1-48", "48" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
check(ok, "getmax maxed callback" .. (ok and "" or (" -- " .. tostring(err))))
ok, err = tick()
check(ok, "tick when maxed" .. (ok and "" or (" -- " .. tostring(err))))
check(KT.API.Mode:is(KT.API.Mode.Interactive), "exits to Interactive when already maxed")
check(TIMERS["KT:Kaioken"] == nil, "no timer left when already maxed")


---------------------------------------------------------------------------
-- 8. Room for Accelerated Mastery: extra_room and the fallback
---------------------------------------------------------------------------
realprint("=== PHASE: extra room ===")
check(require(PKG):constant("kaioken.extra_room") == 2, "extra_room defaults to 2")
KT.Player.MKaioken = 20
KT.Player.Kaioken = 0
KT.Player.Fatigue = 1000
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "toggle on for room" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "Syntax: Kaioken 1-120", "120" }
ok, err = pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
SENT = {}
ok, err = tick(); check(ok, "tick room" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 31"), "trains at mastery + 11 by default")

require(PKG):set_constant("kaioken.extra_room", 0)
SENT = {}
ok, err = tick(); check(ok, "tick room 0" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 29"), "extra_room 0 is the old mastery + 9")

require(PKG):set_constant("kaioken.extra_room", 3)
-- the game won't hold 32: three asks, then it steps down to 31
for _ = 1, 3 do SENT = {}; tick() end
check(table.contains(SENT, "kaioken 32"), "asked for mastery + 12 three times")
SENT = {}
ok, err = tick(); check(ok, "tick fallback" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 31"), "steps down when the level doesn't hold (sent: " .. table.concat(SENT, " | ") .. ")")
KT.Player.Kaioken = 31
SENT = {}
tick()
check(not table.contains(SENT, "kaioken 32"), "remembers the lower room")
-- mastery gains 3 at once: the room keeps up
KT.Player.MKaioken = 23
SENT = {}
tick()
check(table.contains(SENT, "kaioken 34"), "follows a 3-point gain with the same room")
-- a lagging prompt doesn't count as a refusal once the level is reached
KT.Player.Kaioken = 34
tick()
check(KT.API.Kaioken.asked == nil, "reaching the level clears the pending ask")
require(PKG):set_constant("kaioken.extra_room", 2)
pcall(toggle_fn)
check(KT.API.Mode:is(KT.API.Mode.Interactive), "toggled off")

-- the last stretch: max 128, train at 128 until mastery reaches 120, never stepping down
realprint("=== PHASE: last stretch ===")
KT.Player.MKaioken = 117
KT.Player.Kaioken = 0
KT.Player.Fatigue = 1000
pcall(toggle_fn)
matches = { "Syntax: Kaioken 1-128", "128" }
pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
KT.API.Kaioken.room_cap = 0   -- an earlier step-down must not hold it back now
local seen = {}
for _ = 1, 5 do SENT = {}; tick(); for _, c in ipairs(SENT) do seen[c] = true end end
check(seen["kaioken 128"] and not seen["kaioken 127"] and not seen["kaioken 125"],
  "near the ceiling: trains at kaioken 128 and never steps down")
KT.Player.MKaioken = 119
SENT = {}; tick()
check(table.contains(SENT, "kaioken 128"), "mastery 119: still kaioken 128")
KT.Player.MKaioken = 120
SENT = {}; tick()
check(table.contains(SENT, "kaioken getmax"), "mastery 120 (128 - 8): checks the ceiling before stopping")
matches = { "Syntax: Kaioken 1-128", "128" }
pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
SENT = {}; tick()
check(table.contains(SENT, "kaioken 120") and KT.API.Mode:is(KT.API.Mode.Interactive), "mastered at 120: stops")

---------------------------------------------------------------------------
-- 7. Config aliases
---------------------------------------------------------------------------
-- stale mastery from another character (120) must not end training: wait for 'status'
realprint("=== PHASE: stale mastery ===")
KT.Player.MKaioken = 120
KT.Player.Kaioken = 0
KT.Player.Fatigue = 1000
SENT = {}
pcall(raw_toggle)
check(KT.Player.MKaioken == nil, "old mastery forgotten on enable")
matches = { "Syntax: Kaioken 1-48", "48" }
pcall(TEMP_TRIGGERS[#TEMP_TRIGGERS].func)
SENT = {}
ok, err = tick(); check(ok, "tick unknown mastery" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0 and KT.API.Mode:is(KT.API.Mode.Kaioken), "no kaioken change and still training while mastery unknown")
KT.Player.MKaioken = 5                              -- "You have mastered kaioken x5."
SENT = {}
ok, err = tick(); check(ok, "tick mastery 5" .. (ok and "" or (" -- " .. tostring(err))))
check(table.contains(SENT, "kaioken 16"), "mastery 5: trains at 5 + 9 + 2 = 16 (sent: " .. table.concat(SENT, " | ") .. ")")
pcall(raw_toggle)

realprint("=== PHASE: config aliases ===")
matches = { "KT features" }
ok, err = pcall(load_pkg_file("aliases/KT_feature.lua")); check(ok, "KT features alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "KT feature MSDP.debug on", "MSDP.debug", "on" }
ok, err = pcall(load_pkg_file("aliases/KT_feature_toggle.lua")); check(ok, "KT feature toggle alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):feature("MSDP.debug") == true, "feature persisted to on")
matches = { "KT constants", nil }
ok, err = pcall(load_pkg_file("aliases/KT_constant.lua")); check(ok, "KT constants alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "KT constant MSDP.timeout=15", "MSDP.timeout", "15" }
ok, err = pcall(load_pkg_file("aliases/KT_constant_set.lua")); check(ok, "KT constant set alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):constant("MSDP.timeout") == 15, "constant persisted")
matches = { "KT" }
ok, err = pcall(load_pkg_file("aliases/KT_Help.lua")); check(ok, "KT help alias" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- Prompt watch: warns only when lines keep coming without a recognised prompt
---------------------------------------------------------------------------
realprint("=== PHASE: prompt watch ===")
do
  local lineTrig
  for _, tr in ipairs(TEMP_TRIGGERS) do if tr.pattern == "^" then lineTrig = tr end end
  check(lineTrig ~= nil, "every-line counter trigger registered")
  local function warnings()
    local n = 0
    for _, l in ipairs(LOG) do if l:find("No prompt recognised", 1, true) then n = n + 1 end end
    return n
  end
  local tick = TIMERS["KT:LastPrompt"].func
  raiseEvent("KT.onPrompt")
  LOG = {}
  WATCH_TIMES["KT.prompt"] = 4000 -- idle over an hour, nothing arrived
  tick()
  check(warnings() == 0, "no warning when idle (no lines since the last prompt)")
  for _ = 1, 5 do lineTrig.func() end
  tick()
  check(warnings() == 0, "no warning for the few lines right after an idle spell")
  for _ = 1, 150 do lineTrig.func() end
  tick(); tick()
  check(warnings() == 1, "warns once when lines keep coming without a prompt")
  raiseEvent("KT.onPrompt")
  check(WATCH_TIMES["KT.prompt"] == 0, "a prompt resets the stopwatch")
  for _ = 1, 150 do lineTrig.func() end
  tick()
  check(warnings() == 1, "no warning right after a prompt")
  WATCH_TIMES["KT.prompt"] = 400
  tick()
  check(warnings() == 2, "warns again after a prompt re-armed it")
  raiseEvent("KT.onPrompt")
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
realprint("")
realprint(("=== RESULT: %d passed, %d failed ==="):format(passes, #failures))
for _, m in ipairs(failures) do realprint("  FAILED: " .. m) end
if #failures > 0 then error("harness failures", 0) end
