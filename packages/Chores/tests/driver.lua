-- Mudlet environment simulator + Chores package smoke test.
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

function killTrigger(id) end
function enableTrigger(name) end
function disableTrigger(name) end
function setTriggerStayOpen(name, n) end
function gagLine() end

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
local PKG = "Chores"
local module_cache = {}

local function load_pkg_file(relpath)
  local src = readfile(ROOT .. "/" .. relpath)
  assert(src, "cannot read " .. relpath)
  src = src:gsub("__PKGNAME__", PKG):gsub("__VERSION__", "26.07.27")
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

local function tick()
  local t = TIMERS["CH:Chores"]
  if not t then return false, "CH:Chores timer no longer exists" end
  return pcall(t.func)
end

local function sent(cmd)
  return table.contains(SENT, cmd)
end

---------------------------------------------------------------------------
-- 1. Load
---------------------------------------------------------------------------
realprint("=== PHASE: script load ===")
local ok, err = pcall(function() require(PKG):register(PKG, "26.07.27") end)
check(ok, "registration script" .. (ok and "" or (" -- " .. tostring(err))))

for _, s in ipairs({
  "scripts/Core.lua", "scripts/Bot.lua",
  "scripts/Event Handlers/MSDP.lua", "scripts/Event Handlers/Prompt_Events.lua",
  "scripts/Event Handlers/Connection_Events.lua",
}) do run_script(s) end

check(CH ~= nil, "CH global namespace exists")
check(CH and CH.API and CH.API.Chores and CH.API.Chores.toggle ~= nil, "CH.API.Chores:toggle exists")
check(CH.API.Chores.mode == "off", "no auto-start: off after load")
check(TIMERS["CH:Chores"] == nil, "no timer running after load")

---------------------------------------------------------------------------
-- 2. Connect + MSDP + prompt
---------------------------------------------------------------------------
realprint("=== PHASE: connection ===")
raiseEvent("sysConnectionEvent")
check(#MSDP_SENT > 0 and MSDP_SENT[#MSDP_SENT][1] == "REPORT", "MSDP REPORT sent on sysConnectionEvent")

local feed = { FATIGUE = "900", FATIGUE_MAX = "1000", KI = "1000", KI_MAX = "1000",
  POWERLEVEL = "2000000000", POWERLEVEL_MAX = "2000000000", BASE_PL = "2000000000",
  UPDATE_EPOCH = tostring(fake_epoch) }
for k, v in pairs(feed) do
  msdp[k] = v
  raiseEvent("msdp." .. k)
end
check(CH.Player.Fatigue == 900, "fatigue populated from MSDP")
check(CH.Player.BasePl == 2000000000, "base power level populated from MSDP")

local prompt_fn = load_pkg_file("triggers/Prompt.lua")
ok, err = pcall(prompt_fn); check(ok, "Prompt trigger script" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.Toggles.firstprompt == true, "firstprompt set after prompt")

-- configure paths
local ck_mod = require(PKG)
ck_mod:set_constant("chores.fishing_path", "recall;d;d;w")
ck_mod:set_constant("chores.rest_path", "e;u;u")

---------------------------------------------------------------------------
-- 3. Fishing basics
---------------------------------------------------------------------------
realprint("=== PHASE: fishing ===")
SENT = {}
local toggle_fn = load("CH.API.Chores:toggle(matches[2])")
matches = { "chores fish", "fish" }
ok, err = pcall(toggle_fn); check(ok, "chores fish" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "fish" and CH.API.Chores.activity == "fishing", "fishing mode on")
check(sent("castout"), "initial castout")
check(TIMERS["CH:Chores"] ~= nil, "chores timer registered")

-- a bite: reelin + immediate recast
SENT = {}
local tug_fn = load("CH.API.Chores:tug()")
ok, err = pcall(tug_fn); check(ok, "tug trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("reelin") and sent("castout"), "reelin then recast on tug")

-- multi-catch: 'another tug' reels only, no recast
SENT = {}
local another_fn = load("CH.API.Chores:another_tug()")
ok, err = pcall(another_fn); check(ok, "another tug trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("reelin") and not sent("castout"), "reelin only on another tug (sent: " .. table.concat(SENT, " | ") .. ")")

-- an empty reel puts no line back: cast again
local empty_fn = load("CH.API.Chores:line_empty()")
SENT = {}
ok, err = pcall(another_fn); check(ok, "another tug before empty reel" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
ok, err = pcall(empty_fn); check(ok, "caught-nothing trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("castout"), "recast after a reel that caught nothing (sent: " .. table.concat(SENT, " | ") .. ")")

-- but a normal tug already recast, so the same message must not double up
SENT = {}
ok, err = pcall(tug_fn); check(ok, "tug before empty reel" .. (ok and "" or (" -- " .. tostring(err))))
local casts = 0
for _, c in ipairs(SENT) do if c == "castout" then casts = casts + 1 end end
ok, err = pcall(empty_fn); check(ok, "caught-nothing right after a tug" .. (ok and "" or (" -- " .. tostring(err))))
local casts_after = 0
for _, c in ipairs(SENT) do if c == "castout" then casts_after = casts_after + 1 end end
check(casts == 1 and casts_after == 1, "no second cast when the tug already recast")

-- 'you aren't even fishing' means no line at all
CH.API.Chores.line_out = false
SENT = {}
ok, err = pcall(empty_fn); check(ok, "not-fishing trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("castout"), "recast when we were not fishing at all")

-- and neither message acts when the bot is off task
CH.API.Chores.activity = "quest"
CH.API.Chores.line_out = false
SENT = {}
ok, err = pcall(empty_fn); check(ok, "empty reel off task" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "empty-reel messages ignored outside fishing")
CH.API.Chores.activity = "fishing"

-- tangle: recast
SENT = {}
local tangle_fn = load("CH.API.Chores:tangle()")
ok, err = pcall(tangle_fn); check(ok, "tangle trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("castout"), "recast on tangle")

-- heartbeat: no bite for recast_timeout -> recast
SENT = {}
ok, err = tick(); check(ok, "tick idle" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("castout"), "no recast before timeout")
fake_epoch = fake_epoch + 121
SENT = {}
ok, err = tick(); check(ok, "tick heartbeat" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("castout"), "recast after recast_timeout with no bite")

---------------------------------------------------------------------------
-- 3b. Bad fishing spot: walk back, and give up after three strikes
---------------------------------------------------------------------------
realprint("=== PHASE: bad spot ===")
local bad_fn = load("CH.API.Chores:bad_spot()")
SENT = {}
ok, err = pcall(bad_fn); check(ok, "bad spot trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("recall") and sent("w") and sent("castout"), "walked fishing_path back and recast (sent: " .. table.concat(SENT, " | ") .. ")")
check(CH.API.Chores.activity == "fishing", "still fishing after bad spot")

-- a bite resets the strike counter
ok, err = pcall(tug_fn); check(ok, "tug resets bad spot counter" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.bad_spots == nil, "bad spot counter reset by a bite")

-- three consecutive strikes -> stop with a warning
ok = pcall(bad_fn); ok = pcall(bad_fn)
SENT = {}
ok, err = pcall(bad_fn); check(ok, "third bad spot" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "off" and TIMERS["CH:Chores"] == nil, "stopped after three bad spots")
check(not sent("reelin"), "no stray reelin when stopping on bad spot")
local spot_warned = false
for _, l in ipairs(LOG) do
  if l:find("check `chores.fishing_path`", 1, true) then spot_warned = true end
end
check(spot_warned, "warned to check fishing_path")

-- restart fishing for the following phases
matches = { "chores fish", "fish" }
ok, err = pcall(toggle_fn); check(ok, "chores fish restart" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 3c. The mud says we are too exhausted to fish
---------------------------------------------------------------------------
realprint("=== PHASE: too exhausted ===")
local exhausted_fn = load("CH.API.Chores:too_exhausted()")
SENT = {}
ok, err = pcall(exhausted_fn); check(ok, "too-exhausted trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "resting", "went to rest on the exhausted message")
check(sent("e") and sent("u") and sent("land") and sent("sleep"),
  "walked rest_path, landed and slept (sent: " .. table.concat(SENT, " | ") .. ")")
check(not sent("reelin"), "no reelin when the cast was refused")

-- and it is ignored when we are not fishing
SENT = {}
ok, err = pcall(exhausted_fn); check(ok, "too-exhausted while resting" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "exhausted message ignored outside fishing")

-- wake back up for the following phases
CH.Player.Fatigue = 1000
SENT = {}
ok, err = tick(); check(ok, "tick rested after exhaustion" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("wake") and sent("castout"), "resumed fishing after the exhaustion rest")
CH.Player.Fatigue = 900

---------------------------------------------------------------------------
-- 4. Rest cycle
---------------------------------------------------------------------------
realprint("=== PHASE: rest ===")
CH.Player.Fatigue = 100 -- 10% < 20%
SENT = {}
ok, err = tick(); check(ok, "tick fatigued" .. (ok and "" or (" -- " .. tostring(err))))
check(SENT[1] == "reelin", "line reeled in before leaving to rest (sent: " .. table.concat(SENT, " | ") .. ")")
check(sent("e") and sent("u") and sent("sleep"), "walked rest_path and slept (sent: " .. table.concat(SENT, " | ") .. ")")
check(SENT[#SENT] == "sleep" and SENT[#SENT - 1] == "land", "landed right before sleeping")
check(CH.API.Chores.activity == "resting", "activity resting")

SENT = {}
ok, err = tick(); check(ok, "tick still tired" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "stays asleep while tired")

CH.Player.Fatigue = 1000
SENT = {}
ok, err = tick(); check(ok, "tick rested" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("wake") and sent("recall") and sent("w") and sent("castout"),
  "woke, walked fishing_path, recast (sent: " .. table.concat(SENT, " | ") .. ")")
check(CH.API.Chores.activity == "fishing", "back to fishing after rest")

---------------------------------------------------------------------------
-- 5. Quest happy path (mode both)
---------------------------------------------------------------------------
realprint("=== PHASE: quest happy path ===")
SENT = {}
matches = { "chores both", "both" }
ok, err = pcall(toggle_fn); check(ok, "chores both" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "both", "mode both")
CH.API.Chores.next_grave = nil -- the gravedigger gets its own phase
check(CH.API.Chores.activity == "quest", "quest starts immediately on toggle")
check(sent("recall") and sent("focus 'instant' roshi"), "recall + instant to roshi at toggle time")
check(sent("reelin"), "prior fishing line reeled in during the mode switch")

SENT = {}
local roshi_fn = load("CH.API.Chores:roshi_seen()")
ok, err = pcall(roshi_fn); check(ok, "roshi trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue royal cook"), "pursued the cook after roshi confirmed")

SENT = {}
local cookq_fn = load("CH.API.Chores:cook_asked()")
ok, err = pcall(cookq_fn); check(ok, "cook question trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("say yes"), "accepted the delivery")

SENT = {}
matches = { "This must go to Sir Maximillion, don't mess it up now!", "Maximillion" }
local knight_fn = load("CH.API.Chores:knight_named(matches[2])")
ok, err = pcall(knight_fn); check(ok, "knight trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue maximillion") and sent("give jerky maximillion"),
  "delivered to the lowercased knight (sent: " .. table.concat(SENT, " | ") .. ")")
check(sent("castout") and CH.API.Chores.activity == "fishing", "back to fishing after delivery")
check(CH.API.Chores.next_quest == fake_epoch + 300, "next quest in a full period")

---------------------------------------------------------------------------
-- 6. Cooldown reschedule
---------------------------------------------------------------------------
realprint("=== PHASE: cooldown reschedule ===")
fake_epoch = fake_epoch + 300
SENT = {}
ok, err = tick(); check(ok, "tick quest due again" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "second quest started")

ok, err = pcall(roshi_fn); check(ok, "roshi trigger again" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
local cd_fn = load("CH.API.Chores:quest_cooldown(tonumber(matches[2]))")
matches = { "Royal Cook says, 'I just sent you on a delivery 4 minutes ago! Come back later.'", "4" }
ok, err = pcall(cd_fn); check(ok, "cooldown trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "back to fishing after cooldown reply")
check(CH.API.Chores.next_quest == fake_epoch + 60, "next attempt in period minus reported minutes")

-- the seconds-remaining cooldown variant
fake_epoch = fake_epoch + 60
ok, err = tick(); check(ok, "tick quest for seconds cooldown" .. (ok and "" or (" -- " .. tostring(err))))
ok = pcall(roshi_fn)
local cdleft_fn = load("CH.API.Chores:quest_cooldown_left(tonumber(matches[2]), matches[3])")
matches = { "Royal Cook says, 'I just sent you on a delivery! Come back in 11 seconds.'", "11", "seconds" }
SENT = {}
ok, err = pcall(cdleft_fn); check(ok, "cooldown-left trigger (seconds)" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "back to fishing after seconds cooldown")
check(CH.API.Chores.next_quest == fake_epoch + 16, "next attempt in reported seconds plus buffer")

-- and a minutes-remaining variant just in case the mud switches units
fake_epoch = fake_epoch + 16
ok, err = tick(); check(ok, "tick quest for minutes cooldown" .. (ok and "" or (" -- " .. tostring(err))))
ok = pcall(roshi_fn)
matches = { "Royal Cook says, 'I just sent you on a delivery! Come back in 2 minutes.'", "2", "minutes" }
ok, err = pcall(cdleft_fn); check(ok, "cooldown-left trigger (minutes)" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.next_quest == fake_epoch + 125, "next attempt in reported minutes plus buffer")
-- realign so the next phase's +60 tick lands exactly on the schedule
fake_epoch = fake_epoch + 65

---------------------------------------------------------------------------
-- 7. Roshi missing: 3 attempts then abort
---------------------------------------------------------------------------
realprint("=== PHASE: roshi retries ===")
fake_epoch = fake_epoch + 60
SENT = {}
ok, err = tick(); check(ok, "tick quest attempt 3" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "third quest started")

fake_epoch = fake_epoch + 11
SENT = {}
ok, err = tick(); check(ok, "tick roshi retry 2" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("focus 'instant' roshi"), "instant retried (2nd attempt)")
fake_epoch = fake_epoch + 11
SENT = {}
ok, err = tick(); check(ok, "tick roshi retry 3" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("focus 'instant' roshi"), "instant retried (3rd attempt)")
fake_epoch = fake_epoch + 11
SENT = {}
ok, err = tick(); check(ok, "tick roshi give up" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("focus 'instant' roshi"), "no 4th instant attempt")
check(CH.API.Chores.activity == "fishing", "aborted back to fishing")

---------------------------------------------------------------------------
-- 8. Quest preempts resting
---------------------------------------------------------------------------
realprint("=== PHASE: quest preempts rest ===")
CH.Player.Fatigue = 100
SENT = {}
ok, err = tick(); check(ok, "tick tired again" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "resting", "resting while tired")

fake_epoch = fake_epoch + 400 -- quest due (period after the abort)
SENT = {}
ok, err = tick(); check(ok, "tick quest while resting" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("wake"), "woke up for the quest")
check(not sent("reelin"), "no reelin when the quest starts from rest")
check(CH.API.Chores.activity == "quest", "quest preempted the rest")
-- finish it quickly
ok = pcall(roshi_fn); ok = pcall(cookq_fn)
matches = { "This must go to Sir Lancelot, don't mess it up now!", "Lancelot" }
SENT = {}
ok, err = pcall(knight_fn); check(ok, "knight trigger (Lancelot)" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("give jerky lancelot"), "second knight name parsed")
CH.Player.Fatigue = 1000 -- rested enough to keep fishing

---------------------------------------------------------------------------
-- 9. Boss fish routine (placeholder triggers call these)
---------------------------------------------------------------------------
realprint("=== PHASE: boss fish ===")
local bossa_fn = load("CH.API.Chores:boss_appeared()")

-- unconfigured: warn and stay on task
ck_mod:set_constant("chores.boss_attack", "")
SENT = {}
ok, err = pcall(bossa_fn); check(ok, "boss appeared unconfigured" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "unconfigured boss does not change activity")
local boss_warned = false
for _, l in ipairs(LOG) do
  if l:find("chores.boss_attack", 1, true) then boss_warned = true end
end
check(boss_warned, "warned about unset boss_attack")

ck_mod:set_constant("chores.boss_before", "focus 'barrier';powerup")
ck_mod:set_constant("chores.boss_attack", "kame")
ck_mod:set_constant("chores.boss_after", "get all corpse")
SENT = {}
ok, err = pcall(bossa_fn); check(ok, "boss appeared" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("focus 'barrier'") and sent("powerup"), "boss_before commands sent")
check(CH.API.Chores.activity == "boss", "activity boss")

SENT = {}
ok, err = tick(); check(ok, "tick boss fight" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("kame"), "boss attack repeated on tick")

-- fight engages via MSDP; the death line ends it even though the MSDP
-- opponent feed never clears (the exact case that stuck the bot in game)
local died_fn = load("CH.API.Chores:something_died()")
CH.Target.name = "Great White Shark"
ok, err = tick(); check(ok, "tick boss engaged" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
ok, err = pcall(died_fn); check(ok, "kill line trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("get all corpse") and sent("castout"), "boss_after then resume casting on death line")
check(CH.API.Chores.activity == "fishing", "fishing again after boss")
check(CH.Target.name == "", "stale MSDP opponent cleared by the death line")

---------------------------------------------------------------------------
-- 10. Rival ambush while traveling
---------------------------------------------------------------------------
realprint("=== PHASE: rival ambush ===")
local rival_fn = load("CH.API.Chores:rival_attacked(multimatches[2][2])")

-- unconfigured: warn and stay on task
multimatches = { {}, { "Protei the Tuffle flies out of nowhere and attacks you!", "Protei" } }
SENT = {}
ok, err = pcall(rival_fn); check(ok, "rival trigger unconfigured" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "unconfigured rival does not change activity")
local warned = false
for _, l in ipairs(LOG) do
  if l:find("chores.rival_attack", 1, true) then warned = true end
end
check(warned, "warned about unset rival_attack")

-- configured: fight, then resume fishing
ck_mod:set_constant("chores.rival_before", "focus 'unravel' $target")
ck_mod:set_constant("chores.rival_attack", "kame")
ck_mod:set_constant("chores.rival_after", "get all corpse")
SENT = {}
ok, err = pcall(rival_fn); check(ok, "rival trigger configured" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("focus 'unravel' protei"), "rival_before with $target substituted")
check(sent("kame protei"), "first attack sent immediately")
check(CH.API.Chores.activity == "rival", "activity rival")

-- fight engages (MSDP opponent appears), keeps attacking
CH.Target.name = "Protei the Tuffle"
SENT = {}
ok, err = tick(); check(ok, "tick rival engaged" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("kame protei"), "keeps attacking while opponent present")

-- opponent gone -> fight over -> resume fishing
CH.Target.name = ""
SENT = {}
ok, err = tick(); check(ok, "tick rival over" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("get all corpse"), "rival_after with $target substituted")
check(sent("castout") and CH.API.Chores.activity == "fishing", "resumed fishing after rival")

-- a kill line while just fishing is a no-op
SENT = {}
ok, err = pcall(load("CH.API.Chores:something_died()")); check(ok, "kill line while fishing" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0 and CH.API.Chores.activity == "fishing", "kill line ignored outside fights")

-- rival mid-quest: fight, then restart the quest from the top
fake_epoch = fake_epoch + 400
SENT = {}
ok, err = tick(); check(ok, "tick quest before rival" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "quest running")
multimatches = { {}, { "Grumnir the Dwarf flies out of nowhere and attacks you!", "Grumnir" } }
SENT = {}
ok, err = pcall(rival_fn); check(ok, "rival trigger mid-quest" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("kame grumnir"), "fights the mid-quest rival")
CH.Target.name = "Grumnir the Dwarf"
ok, err = tick(); check(ok, "tick mid-quest rival" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
ok, err = pcall(load("CH.API.Chores:something_died()")); check(ok, "mid-quest rival death line" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue royal cook"), "resumes at the cook after the fight (no recall/instant)")
check(not sent("recall") and not sent("focus 'instant' roshi"), "does not restart the quest from the top")
check(CH.API.Chores.activity == "quest", "activity back to quest")
-- the cook reminds us the delivery was already accepted -> deliver directly
SENT = {}
local remind_fn = load("CH.API.Chores:knight_reminded(matches[2])")
matches = { "Royal Cook exclaims, 'What are you still doing here! I asked you to deliver the jerky to Knight Glenn!'", "Glenn" }
ok, err = pcall(remind_fn); check(ok, "cook reminder trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue glenn") and sent("give jerky glenn"), "delivered to the reminded knight (sent: " .. table.concat(SENT, " | ") .. ")")
check(CH.API.Chores.activity == "fishing", "fishing after reminded delivery")

---------------------------------------------------------------------------
-- 10b. Death recovery
---------------------------------------------------------------------------
realprint("=== PHASE: death recovery ===")
local died_line_fn = load("CH.API.Chores:died()")

-- die mid-rival-fight: abandon the fight, back to the water
multimatches = { {}, { "Vexar the Icer flies out of nowhere and attacks you!", "Vexar" } }
ok, err = pcall(rival_fn); check(ok, "rival before death" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "rival", "fighting the rival")
SENT = {}
ok, err = pcall(died_line_fn); check(ok, "death line mid-fight" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.rival == nil, "rival fight abandoned on death")
check(sent("recall") and sent("castout"), "walked back and recast after death (sent: " .. table.concat(SENT, " | ") .. ")")
check(CH.API.Chores.activity == "fishing", "fishing after death recovery")

-- the dead-room line right after is debounced (no command loop)
SENT = {}
ok, err = pcall(died_line_fn); check(ok, "dead-room line debounced" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "no repeated recovery within the debounce window")

-- die mid-quest: reschedule and go fish
fake_epoch = fake_epoch + 400
ok, err = tick(); check(ok, "tick quest before death" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "quest running before death")
SENT = {}
ok, err = pcall(died_line_fn); check(ok, "death line mid-quest" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "fishing after mid-quest death")
check(CH.API.Chores.next_quest == fake_epoch + 300, "quest rescheduled a full period after death")

-- with the bot off, death lines are ignored
matches = { "chores off", "off" }
ok, err = pcall(toggle_fn); check(ok, "chores off before dead check" .. (ok and "" or (" -- " .. tostring(err))))
fake_epoch = fake_epoch + 20
SENT = {}
ok, err = pcall(died_line_fn); check(ok, "death line while off" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "death line ignored when off")

---------------------------------------------------------------------------
-- 10c. Gravedigger task
---------------------------------------------------------------------------
realprint("=== PHASE: gravedigger ===")
matches = { "chores both", "both" }
ok, err = pcall(toggle_fn); check(ok, "chores both for grave phase" .. (ok and "" or (" -- " .. tostring(err))))
-- finish the cook delivery that starts on toggle
ok = pcall(roshi_fn); ok = pcall(cookq_fn)
matches = { "This must go to Sir Bran, don't mess it up now!", "Bran" }
ok, err = pcall(knight_fn); check(ok, "cook delivery before grave" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "fishing after cook, grave next")
CH.API.Chores.next_quest = fake_epoch + 100000 -- park the cook, isolate the grave

-- the shipped default reaches Billy and does not double the pursue
check(ck_mod:constant("chores.grave_path") == "focus 'instant' gine;pursue gravedigger",
  "grave_path shipped as a default")
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave default path" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("focus 'instant' gine") and sent("pursue gravedigger"),
  "default path traveled toward Billy (sent: " .. table.concat(SENT, " | ") .. ")")
check(not sent("say task"), "does not say task while the pursue may still be walking")
local pursues = 0
for _, c in ipairs(SENT) do
  if c == "pursue gravedigger" then pursues = pursues + 1 end
end
check(pursues == 1, "pursue not duplicated when the path already has one")
-- the tick asks once we have had a moment to arrive, and keeps asking
fake_epoch = fake_epoch + 4
SENT = {}
ok, err = tick(); check(ok, "tick say task" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("say task"), "asked Billy for a task from the tick")
fake_epoch = fake_epoch + 6
SENT = {}
ok, err = tick(); check(ok, "tick say task retry" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("say task"), "keeps asking until Billy answers")
local shovel_fn = load("CH.API.Chores:shovel_found()")

SENT = {}
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 5 is ready to be excavated.'", "5" }
ok, err = pcall(load("CH.API.Chores:grave_plot(tonumber(matches[2]))")); check(ok, "plot 5 with default path" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("locate shovel") and not sent("dig"), "checks for a shovel before heading to the plot")
ok, err = pcall(shovel_fn); check(ok, "shovel found" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("dig"), "digs once the shovel is confirmed")
local digs = 0
ok = pcall(shovel_fn); ok = pcall(shovel_fn) -- locate lists one line per shovel
for _, c in ipairs(SENT) do
  if c == "dig" then digs = digs + 1 end
end
check(digs == 1, "repeated shovel lines do not dig again")
check(CH.API.Chores.activity == "fishing", "fishing again after the default-path run")

-- unconfigured: warn once and disable until set
ck_mod:set_constant("chores.grave_path", "")
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave unconfigured" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("pursue gravedigger"), "no grave run without grave_path")
check(CH.API.Chores.next_grave == nil, "grave disabled until configured")
local grave_warned = 0
for _, l in ipairs(LOG) do
  if l:find("chores.grave_path", 1, true) then grave_warned = grave_warned + 1 end
end
check(grave_warned == 1, "warned once about unset grave_path")

-- the plot routes ship as defaults
check(ck_mod:constant("chores.grave_plot_1") == "w;w;w;w;w;s", "plot 1 route shipped as a default")
check(ck_mod:constant("chores.grave_plot_7") == "w;n;n;n;w;w;w;n", "plot 7 route shipped as a default")
local ok8 = pcall(function() return ck_mod:constant("chores.grave_plot_8") end)
check(not ok8, "plot 8 has no constant")

-- configure and re-arm (travel-only path: the bot adds the pursue itself)
ck_mod:set_constant("chores.grave_path", "recall;board ship")
ck_mod:set_constant("chores.grave_plot_4", "n;n;e")
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave start" .. (ok and "" or (" -- " .. tostring(err))))
check(SENT[1] == "reelin", "line reeled in before leaving to dig")
check(sent("board ship") and sent("pursue gravedigger"),
  "traveled to Billy (sent: " .. table.concat(SENT, " | ") .. ")")
fake_epoch = fake_epoch + 4
SENT = {}
ok, err = tick(); check(ok, "tick say task (configured path)" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("say task"), "asked Billy for a task")
check(CH.API.Chores.activity == "grave", "activity grave")

-- Billy names plot 4 -> walk the plot route and dig
SENT = {}
local plot_fn = load("CH.API.Chores:grave_plot(tonumber(matches[2]))")
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 4 is ready to be excavated.'", "4" }
ok, err = pcall(plot_fn); check(ok, "plot trigger" .. (ok and "" or (" -- " .. tostring(err))))
ok, err = pcall(shovel_fn); check(ok, "shovel found for plot 4" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("n") and sent("e") and sent("dig"), "walked to plot 4 and dug (sent: " .. table.concat(SENT, " | ") .. ")")
local di, gi
for i, c in ipairs(SENT) do
  if c == "dig" then di = i elseif c == "get all" then gi = i end
end
check(di and gi and gi > di, "picked the loot up right after digging")
check(sent("castout") and CH.API.Chores.activity == "fishing", "back to fishing after digging")
check(CH.API.Chores.next_grave == fake_epoch + 300, "next grave task in a full period")

-- a plot with no configured route aborts cleanly
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave again" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "grave", "second grave run started")
SENT = {}
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 8 is ready to be excavated.'", "8" }
ok, err = pcall(plot_fn); check(ok, "unmapped plot trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("dig"), "no dig without a plot route")
check(CH.API.Chores.activity == "fishing", "aborted back to fishing on unmapped plot")
local plot_warned = false
for _, l in ipairs(LOG) do
  if l:find("no route mapped for plot 8", 1, true) then plot_warned = true end
end
check(plot_warned, "warned that the plot has no route")

-- a shipped default route digs without any configuration
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave default route" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 2 is ready to be excavated.'", "2" }
ok, err = pcall(plot_fn); check(ok, "default plot 2 trigger" .. (ok and "" or (" -- " .. tostring(err))))
ok, err = pcall(shovel_fn); check(ok, "shovel found for plot 2" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("w") and sent("s") and sent("dig"), "walked the shipped plot 2 route and dug (sent: " .. table.concat(SENT, " | ") .. ")")

-- Billy has nothing to excavate: reschedule to exactly when he says
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave cooldown run" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "grave", "grave run started for cooldown check")
SENT = {}
local gcd_fn = load("CH.API.Chores:grave_cooldown(tonumber(matches[2]), matches[3])")
matches = { "Gravedigger Billy says, 'Sorry chum, no burial plots need excavating. Check back in 4 minutes.'", "4", "minutes" }
ok, err = pcall(gcd_fn); check(ok, "grave cooldown trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("dig"), "no dig when no plots are ready")
check(CH.API.Chores.activity == "fishing", "back to fishing after the cooldown reply")
check(CH.API.Chores.next_grave == fake_epoch + 245, "next check in the reported minutes plus buffer")

-- and a seconds variant
fake_epoch = fake_epoch + 245
ok, err = tick(); check(ok, "tick grave cooldown seconds" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "Gravedigger Billy says, 'Sorry chum, no burial plots need excavating. Check back in 30 seconds.'", "30", "seconds" }
ok, err = pcall(gcd_fn); check(ok, "grave cooldown seconds trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.next_grave == fake_epoch + 35, "next check in the reported seconds plus buffer")
fake_epoch = fake_epoch + 35

-- no shovel in the locate output: buy one from Billy, then dig
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave shovel-buy run" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 1 is ready to be excavated.'", "1" }
ok, err = pcall(plot_fn); check(ok, "plot 1 assigned" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("locate shovel"), "asked where the shovel is")
SENT = {}
ok, err = tick(); check(ok, "tick while waiting for locate" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "waits for the locate reply before acting")
SENT = {}
local nomatch_fn = load("CH.API.Chores:shovel_missing()")
ok, err = pcall(nomatch_fn); check(ok, "no-match line" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("buy 1"), "bought a shovel from Billy (sent: " .. table.concat(SENT, " | ") .. ")")
check(sent("w") and sent("s") and sent("dig"), "walked the plot 1 route and dug after buying")
check(CH.API.Chores.activity == "fishing", "fishing again after the buy-and-dig run")

-- stray locate output outside the check is ignored
SENT = {}
ok, err = pcall(shovel_fn); check(ok, "stray shovel line" .. (ok and "" or (" -- " .. tostring(err))))
ok, err = pcall(nomatch_fn); check(ok, "stray no-match line" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "locate output ignored outside the shovel step")

-- the timeout still covers a locate that never replies at all
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave silent-locate run" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 2 is ready to be excavated.'", "2" }
ok, err = pcall(plot_fn); check(ok, "plot 2 assigned for silent locate" .. (ok and "" or (" -- " .. tostring(err))))
fake_epoch = fake_epoch + 11
SENT = {}
ok, err = tick(); check(ok, "tick shovel timeout" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("buy 1") and sent("dig"), "timeout falls back to buying and digging")

-- base PL unknown (mud stopped sending BASE_PL): say so instead of going quiet
CH.Player.BasePl = nil
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave with unknown PL" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("pursue gravedigger"), "no grave run without a known base PL")
local unknown_warned = false
for _, l in ipairs(LOG) do
  if l:find("base power level unknown", 1, true) then unknown_warned = true end
end
check(unknown_warned, "explained that base PL is unknown")
-- the score sheet supplies it
multimatches = { {}, { "Base PL:    2,000,000,000   PL Regen: 1", "2,000,000,000" } }
ok, err = pcall(load_pkg_file("triggers/Base_PL.lua"))
check(ok, "Base PL script" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.Player.BasePl == 2000000000, "base PL parsed from the score line")
CH.API.Chores.warned_low_pl = nil

-- under the PL requirement: skip the task, warn once, retry next period
CH.Player.BasePl = 500000000
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave under PL" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("pursue gravedigger"), "no grave run under the PL requirement")
check(CH.API.Chores.activity == "fishing", "keeps fishing when PL is too low")
check(CH.API.Chores.next_grave == fake_epoch + 300, "grave rechecked next period")
local pl_warned = 0
for _, l in ipairs(LOG) do
  if l:find("base power level 500000000 is under 1000000000", 1, true) then pl_warned = pl_warned + 1 end
end
check(pl_warned == 1, "warned once about the power level")
-- and it stays quiet on later attempts
fake_epoch = fake_epoch + 300
SENT = {}
ok, err = tick(); check(ok, "tick grave under PL again" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("pursue gravedigger"), "still skipping under the PL requirement")
pl_warned = 0
for _, l in ipairs(LOG) do
  if l:find("base power level 500000000 is under", 1, true) then pl_warned = pl_warned + 1 end
end
check(pl_warned == 1, "PL warning is not repeated")
-- damaged or suppressed: base PL is what counts, current PL is ignored
CH.Player.BasePl = 2000000000
CH.Player.Pl = 10
CH.Player.MaxPl = 10
CH.API.Chores.next_grave = fake_epoch
SENT = {}
ok, err = tick(); check(ok, "tick grave while damaged" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue gravedigger"), "damaged character still runs the task on base PL")
CH.API.Chores:grave_fail("test cleanup")
CH.Player.Pl = 2000000000
CH.Player.MaxPl = 2000000000

-- Billy nags that the task is already assigned: treat it as the assignment
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave reminder run" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "grave", "grave run started for the reminder")
local remind_grave_fn = load("CH.API.Chores:grave_reminded(tonumber(matches[2]))")
SENT = {}
matches = { "Gravedigger Billy exclaims, 'I already done told you! I need you to go dig up burial plot 5!'", "5" }
ok, err = pcall(remind_grave_fn); check(ok, "grave reminder trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("locate shovel"), "reminder accepted as the plot assignment")
-- a repeated nag for the plot we are already handling is ignored
SENT = {}
ok, err = pcall(remind_grave_fn); check(ok, "repeated grave reminder" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "nag for the plot in progress is ignored")
ok, err = pcall(shovel_fn); check(ok, "shovel for reminded plot" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("dig"), "dug the reminded plot")
check(CH.API.Chores.activity == "fishing", "fishing again after the reminded run")

-- a nag while not on the task at all is ignored
SENT = {}
ok, err = pcall(remind_grave_fn); check(ok, "grave reminder while fishing" .. (ok and "" or (" -- " .. tostring(err))))
check(#SENT == 0, "reminder ignored outside a grave run")

-- a slow pursue: Billy answers well after the old 30s budget
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave slow-pursue run" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "grave", "grave run started for the slow pursue")
for _ = 1, 20 do -- 40 seconds of walking
  fake_epoch = fake_epoch + 2
  ok, err = tick(); check(ok, "tick during slow pursue" .. (ok and "" or (" -- " .. tostring(err))))
end
check(CH.API.Chores.activity == "grave", "still on the grave task after 40s of pursuing")
SENT = {}
matches = { "Gravedigger Billy says, 'Yer in luck Vorrac, plot 2 is ready to be excavated.'", "2" }
ok, err = pcall(plot_fn); check(ok, "late plot assignment" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("locate shovel"), "late plot assignment is still accepted")
ok, err = pcall(shovel_fn); check(ok, "shovel for late plot" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("dig"), "dug the late-assigned plot")

-- no plot line at all: timeout aborts
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave third" .. (ok and "" or (" -- " .. tostring(err))))
fake_epoch = fake_epoch + 91
SENT = {}
ok, err = tick(); check(ok, "tick grave timeout" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "timed-out grave run returns to fishing")

-- dying mid-dig reschedules
fake_epoch = fake_epoch + 300
ok, err = tick(); check(ok, "tick grave fourth" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "grave", "fourth grave run started")
ok, err = pcall(died_line_fn); check(ok, "death during grave" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "fishing", "fishing after dying mid-dig")
check(CH.API.Chores.next_grave == fake_epoch + 300, "grave rescheduled a full period after death")

matches = { "chores off", "off" }
ok, err = pcall(toggle_fn); check(ok, "chores off after grave phase" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- 11. Quest-only mode and off
---------------------------------------------------------------------------
realprint("=== PHASE: quest-only + off ===")
SENT = {}
matches = { "chores quest", "quest" }
ok, err = pcall(toggle_fn); check(ok, "chores quest" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "quest-only starts the quest immediately")
check(not sent("castout"), "quest-only does not cast")
ok = pcall(roshi_fn); ok = pcall(cookq_fn)
matches = { "This must go to Sir Kay, don't mess it up now!", "Kay" }
SENT = {}
ok, err = pcall(knight_fn); check(ok, "knight trigger (Kay)" .. (ok and "" or (" -- " .. tostring(err))))
check(not sent("castout"), "quest-only does not fish afterwards")
check(sent("recall") and sent("w"), "quest-only still walks back to the spot")
check(CH.API.Chores.activity == "idle", "quest-only back to idle")

matches = { "chores off", "off" }
ok, err = pcall(toggle_fn); check(ok, "chores off" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "off" and TIMERS["CH:Chores"] == nil, "stopped and timer deleted")
check(not sent("reelin"), "no reelin when stopping from idle")

-- turning off while actively fishing reels the line in
matches = { "chores fish", "fish" }
ok, err = pcall(toggle_fn); check(ok, "chores fish before off" .. (ok and "" or (" -- " .. tostring(err))))
SENT = {}
matches = { "chores off", "off" }
ok, err = pcall(toggle_fn); check(ok, "chores off while fishing" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("reelin"), "reeled in when turned off while fishing")
check(CH.API.Chores.mode == "off", "off after fishing stop")

-- tug with the bot off still auto-reelins (CK parity) but does not recast
SENT = {}
ok, err = pcall(tug_fn); check(ok, "tug while off" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("reelin") and not sent("castout"), "auto reelin stays, no recast when off")

---------------------------------------------------------------------------
-- 12. Missing fishing_path: warn instead of silently staying put
---------------------------------------------------------------------------
realprint("=== PHASE: missing fishing_path ===")
ck_mod:set_constant("chores.fishing_path", "")
matches = { "chores both", "both" }
ok, err = pcall(toggle_fn); check(ok, "chores both, no path" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.activity == "quest", "quest running immediately, no path")
ok = pcall(roshi_fn)
SENT = {}
matches = { "Royal Cook says, 'I just sent you on a delivery 3 minutes ago! Come back later.'", "3" }
ok, err = pcall(cd_fn); check(ok, "cooldown, no path" .. (ok and "" or (" -- " .. tostring(err))))
local path_warned = 0
for _, l in ipairs(LOG) do
  if l:find("chores.fishing_path", 1, true) and l:find("walk back", 1, true) then path_warned = path_warned + 1 end
end
check(path_warned == 1, "warned once about unset fishing_path")
check(sent("castout") and CH.API.Chores.activity == "fishing", "still resumes casting in place")
matches = { "chores off", "off" }
ok, err = pcall(toggle_fn); check(ok, "chores off after path phase" .. (ok and "" or (" -- " .. tostring(err))))
ck_mod:set_constant("chores.fishing_path", "recall;d;d;w")

---------------------------------------------------------------------------
-- 12b. Bare 'chores' flips between off and both
---------------------------------------------------------------------------
realprint("=== PHASE: bare toggle ===")
matches = { "chores" }
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "bare chores from off" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "both", "bare chores turns on both")
check(CH.API.Chores.activity == "quest" and sent("recall"), "bare toggle runs the quest first")
ok, err = pcall(toggle_fn); check(ok, "bare chores from both" .. (ok and "" or (" -- " .. tostring(err))))
check(CH.API.Chores.mode == "off" and TIMERS["CH:Chores"] == nil, "bare chores turns off again")

---------------------------------------------------------------------------
-- 12c. The trip to the cook is a constant
---------------------------------------------------------------------------
realprint("=== PHASE: cook path constant ===")
check(ck_mod:constant("chores.cook_path") == "recall;focus 'instant' roshi",
  "cook_path shipped as a default")

-- a custom travel-only path is walked, and Roshi is still verified
ck_mod:set_constant("chores.cook_path", "recall;n;e")
matches = { "chores quest", "quest" }
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "toggle with a custom cook path" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("n") and sent("e"), "walked the custom cook path (sent: " .. table.concat(SENT, " | ") .. ")")
check(not sent("focus 'instant' roshi"), "the old hardcoded instant is gone")
check(CH.API.Chores.quest.step == "roshi", "still verifies Roshi on a travel-only path")
ok = pcall(roshi_fn)
check(CH.API.Chores.quest.step == "cook", "Roshi confirmation advances to the cook")

-- a path that pursues the cook itself skips the Roshi check
matches = { "chores off", "off" }; pcall(toggle_fn)
ck_mod:set_constant("chores.cook_path", "recall;focus 'instant' roshi;pursue royal cook")
matches = { "chores quest", "quest" }
SENT = {}
ok, err = pcall(toggle_fn); check(ok, "toggle with a pursuing cook path" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("pursue royal cook"), "the path took us to the cook")
check(CH.API.Chores.quest.step == "cook", "Roshi step skipped when the path pursues")
SENT = {}
ok, err = pcall(cookq_fn); check(ok, "cook question after a pursuing path" .. (ok and "" or (" -- " .. tostring(err))))
check(sent("say yes"), "accepted the delivery without a Roshi confirmation")

matches = { "chores off", "off" }; pcall(toggle_fn)
ck_mod:set_constant("chores.cook_path", "recall;focus 'instant' roshi")

---------------------------------------------------------------------------
-- 13. Config aliases
---------------------------------------------------------------------------
realprint("=== PHASE: config aliases ===")
matches = { "CH features" }
ok, err = pcall(load_pkg_file("aliases/CH_feature.lua")); check(ok, "CH features alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "CH constants", nil }
ok, err = pcall(load_pkg_file("aliases/CH_constant.lua")); check(ok, "CH constants alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { 'CH constant chores.quest_period=10', "chores.quest_period", "10" }
ok, err = pcall(load_pkg_file("aliases/CH_constant_set.lua")); check(ok, "CH constant set alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):constant("chores.quest_period") == 10, "constant persisted")
matches = { "CH" }
ok, err = pcall(load_pkg_file("aliases/CH_Help.lua")); check(ok, "CH help alias" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
realprint("")
realprint(("=== RESULT: %d passed, %d failed ==="):format(passes, #failures))
for _, m in ipairs(failures) do realprint("  FAILED: " .. m) end
if #failures > 0 then error("harness failures", 0) end
