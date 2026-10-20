-- Mudlet environment simulator + Score package smoke test.
-- Runs the real package sources under fengari (Lua 5.3) with stubbed Mudlet APIs.

local ROOT = SRC_ROOT or "src" -- injected by runner.js

---------------------------------------------------------------------------
-- Test bookkeeping
---------------------------------------------------------------------------
local realprint = print -- captured before the stubs redirect print into OUT
local failures = {}
local passes = 0
local function check(cond, msg)
  if cond then
    passes = passes + 1
    realprint("PASS: " .. msg)
  else
    table.insert(failures, msg)
    realprint("FAIL: " .. msg)
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
string.trim = smt.trim

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
OUT = {}
GAGGED = 0
HANDLERS = {}
connected = true

local function record(s)
  table.insert(OUT, tostring(s))
end

function cecho(s) record(s) end
function echo(s) record(s) end
function display(v) record(tostring(v)) end
function print(...)
  local parts = {}
  for _, v in ipairs({ ... }) do table.insert(parts, tostring(v)) end
  record(table.concat(parts, " "))
end
function gagLine() GAGGED = GAGGED + 1 end

function send(cmd) table.insert(SENT, cmd) end
function sendMSDP(...) table.insert(MSDP_SENT, { ... }) end

function raiseEvent(event, ...)
  local hs = HANDLERS[event]
  if not hs then return end
  for key, h in pairs(hs) do
    local ok, err = pcall(h, event, ...)
    if not ok then check(false, "handler '" .. key .. "' errored: " .. tostring(err)) end
  end
end
function registerNamedEventHandler(user, name, event, func)
  HANDLERS[event] = HANDLERS[event] or {}
  HANDLERS[event][user .. "/" .. name] = func
  return true
end
function registerNamedTimer() return true end
function deleteNamedTimer() return true end
function tempTimer(secs, func) local ok, e = pcall(func); if not ok then check(false, "tempTimer: " .. tostring(e)) end end
function setTriggerStayOpen() end
function killTrigger() end
function enableTrigger() end
function disableTrigger() end
function createStopWatch(n) return n end
function getStopWatchTime() return 0 end
function resetStopWatch() end
function getEpoch() return 1000000 end
function getConnectionInfo() return "ckmud", 4000, connected end
function getConfig()
  return { enableGMCP = false, enableMNES = true, enableMSDP = true, enableMSP = false, enableMSSP = false, enableMTTS = true }
end
function setConfig() end
function reconnect() end
function getMudletHomeDir() return "/fake" end
function installPackage() end
function uninstallPackage() end

msdp = {}

db = {}
function db:create(dbname, schema)
  local out = {}
  for sheetname, fields in pairs(schema) do
    local sheet = { __rows = {} }
    for fname in pairs(fields) do
      if fname:sub(1, 1) ~= "_" then sheet[fname] = { sheet = sheet, field = fname } end
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
function db:eq(fr, v) return { op = "eq", field = fr.field, value = v } end
function db:not_in(fr, l) return { op = "not_in", field = fr.field, list = l } end
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
    elseif crit.op == "not_in" then del = not table.contains(crit.list, r[crit.field]) end
    if not del then table.insert(keep, r) end
  end
  sheet.__rows = keep
end

yajl = { to_string = function(v) return v end, to_value = function(v) return v end }

---------------------------------------------------------------------------
-- Package loader
---------------------------------------------------------------------------
local PKG = "Score"
local module_cache = {}

local function load_pkg_file(relpath)
  local src = readfile(ROOT .. "/" .. relpath)
  assert(src, "cannot read " .. relpath)
  src = src:gsub("__PKGNAME__", PKG):gsub("__VERSION__", "26.08.09")
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

local function output()
  return table.concat(OUT, "\n")
end

---------------------------------------------------------------------------
-- 1. Load
---------------------------------------------------------------------------
realprint("=== PHASE: script load ===")
-- values already in the msdp table before this package ever loads: MSDP will
-- not resend them until they change, so loading must seed from them
msdp.BASE_PL = "600000000"
msdp.MAX_GRAVITY = "20"

local ok, err = pcall(function() require(PKG):register(PKG, "26.08.09") end)
check(ok, "registration script" .. (ok and "" or (" -- " .. tostring(err))))

for _, s in ipairs({ "scripts/Utils.lua", "scripts/Core.lua", "scripts/Damage.lua",
  "scripts/Sheet.lua", "scripts/MSDP.lua" }) do run_script(s) end

check(SC ~= nil, "SC global namespace exists")
check(SC.API.Sheet and SC.API.Sheet.show, "SC.API.Sheet:show exists")
check(SC.Player.BasePl == 600000000, "seeded base PL already in the msdp table (got " .. tostring(SC.Player.BasePl) .. ")")
check(SC.Player.MaxGravity == 20, "seeded max gravity already in the msdp table")

---------------------------------------------------------------------------
-- 2. MSDP feed
---------------------------------------------------------------------------
realprint("=== PHASE: msdp ===")
raiseEvent("sysConnectionEvent")
check(#MSDP_SENT > 0 and MSDP_SENT[#MSDP_SENT][1] == "REPORT", "MSDP REPORT sent on connect")

local feed = {
  POWERLEVEL = "900000000", POWERLEVEL_MAX = "1000000000", BASE_PL = "600000000",
  KI = "5000", KI_MAX = "10000", GODKI = "400", GODKI_MAX = "500",
  STR = "300", INT = "400", WIS = "500", SPD = "200", CON = "250",
  STR_BASE = "290", INT_BASE = "380", WIS_BASE = "480", SPD_BASE = "150", CON_BASE = "240",
  DAMROLL = "100", HITROLL = "120", ZENNI = "130000000", MAX_GRAVITY = "20",
}
for k, v in pairs(feed) do
  msdp[k] = v
  raiseEvent("msdp." .. k)
end
check(SC.Player.BasePl == 600000000, "base PL populated")
check(SC.Player.Stats.INT == 400, "stats populated")
check(SC.Player.BaseStats.SPD == 150, "base stats populated")

---------------------------------------------------------------------------
-- 3. Computed values
---------------------------------------------------------------------------
realprint("=== PHASE: computed values ===")
local Sheet = SC.API.Sheet
check(Sheet:item_tier(600000000) == 6, "tier 6 at 600M base PL")
check(Sheet:item_tier(999999) == 0, "tier 0 below the first threshold")
check(Sheet:item_tier(9000000000) == 10, "tier 10 at the top")
local nt, needed = Sheet:next_tier(600000000)
check(nt == 7 and needed == 900000000, "next tier 7 needs 900M more (got " .. tostring(nt) .. "/" .. tostring(needed) .. ")")
check(Sheet:next_tier(9000000000) == nil, "no next tier at the top")

local stat, value = Sheet:lowest_stat()
check(stat == "SPD" and value == 150, "lowest base stat is SPD (got " .. tostring(stat) .. ")")

-- CON is reported by MSDP but unused by the game, so it never wins
SC.Player.BaseStats.CON = 11
local stat_c = Sheet:lowest_stat()
check(stat_c == "SPD", "CON ignored even when it is the smallest (got " .. tostring(stat_c) .. ")")
-- floor((1/5000) * 0.06 * 1e9) = 12000, so the max-1 cap wins
check(Sheet:training_gravity() == 19, "training gravity capped to max-1 (got " .. tostring(Sheet:training_gravity()) .. ")")
-- a low-PL character is limited by the formula instead of the cap
local keep_pl = SC.Player.MaxPl
SC.Player.MaxPl = 500000
check(Sheet:training_gravity() == 6, "training gravity 6 at 500k PL (got " .. tostring(Sheet:training_gravity()) .. ")")
SC.Player.MaxPl = keep_pl
check(Sheet:gauntlet_runs() == 5, "5 gauntlet runs from 130M zenni")

-- damage helpers come from the vendored Damage.lua
check(SC.API:ki_dam() > 0 and SC.API:phy_dam() > 0, "damage helpers return numbers")
check(SC.API:ki_dam(true) > SC.API:ki_dam(), "supreme ki damage beats base")
check(SC.API:heal_factor() > 0, "heal factor computed")

---------------------------------------------------------------------------
-- 4. The appended block
---------------------------------------------------------------------------
realprint("=== PHASE: sheet render ===")
OUT = {}
ok, err = pcall(function() Sheet:show() end)
check(ok, "Sheet:show()" .. (ok and "" or (" -- " .. tostring(err))))
local out = output()
check(out:find("PHY DAM", 1, true) and out:find("KI DAM", 1, true), "damage lines rendered")
check(out:find("PHY DAM(U)", 1, true), "ultimate damage line rendered")
check(out:find("HEAL", 1, true), "heal line rendered")
check(out:find("ITEM TIER", 1, true) and out:find("tier 7", 1, true), "tier line shows the next tier")
check(out:find("900,000,000", 1, true), "next-tier gap is formatted with separators")
check(out:find("TRAIN NEXT", 1, true) and out:find("SPD", 1, true), "training hint rendered")
check(out:find("GRAVITY", 1, true) and out:find("19x", 1, true), "gravity hint rendered")
check(out:find("GAUNTLET RUNS", 1, true), "gauntlet runs rendered")

-- top tier renders without a next-tier clause
SC.Player.BasePl = 9000000000
OUT = {}
ok, err = pcall(function() Sheet:show() end)
check(ok, "Sheet:show() at top tier" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("(max)", 1, true), "top tier shows (max)")
SC.Player.BasePl = 600000000

-- missing MSDP data degrades gracefully
local keep = SC.Player.Stats.INT
SC.Player.Stats.INT = nil
OUT = {}
ok, err = pcall(function() Sheet:show() end)
check(ok, "Sheet:show() without stats" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("waiting on MSDP", 1, true), "waits for MSDP instead of erroring")
SC.Player.Stats.INT = keep

---------------------------------------------------------------------------
-- 5. Score trigger scripts
---------------------------------------------------------------------------
realprint("=== PHASE: score triggers ===")
multimatches = { {}, { "Score Information for:Vorricer ", "Vorricer " } }
ok, err = pcall(load('SC.Player.name = string.trim(multimatches[2][2])'))
check(ok, "Score Inject script" .. (ok and "" or (" -- " .. tostring(err))))
check(SC.Player.name == "Vorricer", "name parsed from the real header format")

multimatches = { {}, { "Race: Icer   ", " Icer   " } }
ok, err = pcall(load('SC.Player.race = string.trim(multimatches[2][2])'))
check(ok, "Score Race script" .. (ok and "" or (" -- " .. tostring(err))))
check(SC.Player.race == "Icer", "race parsed from the real race line")

-- base PL from the msdp table directly, even if no change event ever fired
SC.Player.BasePl = nil
msdp.BASE_PL = "600000000"
check(SC.API.Sheet:item_tier() == 6, "tier read straight from the msdp table")

-- with nothing anywhere, the line says so instead of vanishing
SC.Player.BasePl = nil
msdp.BASE_PL = nil
check(SC.API.Sheet:item_tier() == nil, "no tier without a base PL")
OUT = {}
ok, err = pcall(function() SC.API.Sheet:show() end)
check(ok, "show without base PL" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("ITEM TIER", 1, true) and output():find("no base PL yet", 1, true),
  "tier line explains itself when base PL is unknown")

-- the score sheet also supplies it
multimatches = { {}, { "Base PL:    1,001,713,664          PL Regen: 51,291,383 ", "1,001,713,664" } }
ok, err = pcall(load_pkg_file("triggers/Score/Base_PL.lua"))
check(ok, "Base PL script" .. (ok and "" or (" -- " .. tostring(err))))
check(SC.Player.BasePl == 1001713664, "base PL parsed from the score line (got " .. tostring(SC.Player.BasePl) .. ")")
check(SC.API.Sheet:item_tier() == 6, "tier 6 from the parsed base PL")
local nt2, need2 = SC.API.Sheet:next_tier()
check(nt2 == 7 and need2 == 498286336, "needs 498,286,336 more for tier 7 (got " .. tostring(need2) .. ")")
SC.Player.BasePl = 600000000

-- the %-lines are rewritten into real numbers and the original gagged
GAGGED = 0
OUT = {}
multimatches = { {}, { "Ki:  50%  KI REGEN: 3%", "50", "3" } }
ok, err = pcall(load_pkg_file("triggers/Score/Ki_and_Regen.lua"))
check(ok, "Ki and Regen script" .. (ok and "" or (" -- " .. tostring(err))))
check(GAGGED == 1, "original Ki line gagged")
check(output():find("5,000", 1, true), "absolute ki shown")
check(SC.Player.KiRegen == 300, "ki regen computed from the percentage")

GAGGED = 0
OUT = {}
multimatches = { {}, { "GodKi:  80%  GODKI REGEN: 10%", "80", "10" } }
ok, err = pcall(load_pkg_file("triggers/Score/GodKi_and_Regen.lua"))
check(ok, "GodKi and Regen script" .. (ok and "" or (" -- " .. tostring(err))))
check(SC.Player.GKRegen == 50, "godki regen computed from the percentage")

-- and the rewrite can be switched off
require(PKG):set_feature("score.regen", false)
GAGGED = 0
OUT = {}
multimatches = { {}, { "Ki:  50%  KI REGEN: 3%", "50", "3" } }
ok, err = pcall(load_pkg_file("triggers/Score/Ki_and_Regen.lua"))
check(ok, "Ki script with regen off" .. (ok and "" or (" -- " .. tostring(err))))
check(GAGGED == 0, "regen rewrite disabled leaves the line alone")
require(PKG):set_feature("score.regen", true)

-- the extras anchors are top-level triggers with no arming step
local anchor_fn = load("SC.API.Sheet:show_once()")
SC.API.Sheet.last_shown = nil

-- either anchor prints on its own, with no arming step to miss
OUT = {}
ok, err = pcall(anchor_fn); check(ok, "first anchor" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("ITEM TIER", 1, true), "extras printed from the anchor alone")
OUT = {}
ok, err = pcall(anchor_fn); check(ok, "second anchor" .. (ok and "" or (" -- " .. tostring(err))))
check(#OUT == 0, "extras printed only once per sheet")

-- a later score prints again
SC.API.Sheet.last_shown = getEpoch() - 5
OUT = {}
ok, err = pcall(anchor_fn); check(ok, "anchor on a later score" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("ITEM TIER", 1, true), "a later score prints again")

-- and the feature still gates them
require(PKG):set_feature("score.extras", false)
SC.API.Sheet.last_shown = nil
OUT = {}
ok, err = pcall(anchor_fn)
check(ok, "anchor with extras off" .. (ok and "" or (" -- " .. tostring(err))))
check(#OUT == 0, "extras suppressed when disabled")
require(PKG):set_feature("score.extras", true)
SC.API.Sheet.last_shown = nil

---------------------------------------------------------------------------
-- 5b. Gravity on the prompt
---------------------------------------------------------------------------
realprint("=== PHASE: prompt gravity ===")
local prompt_fn = load_pkg_file("triggers/Prompt.lua")
SC.Room.Gravity = 5
SC.Player.MaxGravity = 20
OUT = {}
ok, err = pcall(prompt_fn); check(ok, "prompt trigger" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("5", 1, true) and output():find("20x G", 1, true),
  "prompt shows current and max gravity (got " .. output() .. ")")

-- at or above the max it turns green
SC.Room.Gravity = 20
OUT = {}
ok, err = pcall(prompt_fn); check(ok, "prompt at max gravity" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("green", 1, true), "maxed gravity is highlighted")
SC.Room.Gravity = 5
OUT = {}
ok, err = pcall(prompt_fn)
check(output():find("red", 1, true), "below max stays red")

-- nothing at all until MSDP has both values
SC.Room.Gravity = nil
OUT = {}
ok, err = pcall(prompt_fn); check(ok, "prompt without gravity" .. (ok and "" or (" -- " .. tostring(err))))
check(#OUT == 0, "prompt untouched while gravity is unknown")
SC.Room.Gravity = 5

-- and the feature switches it off
require(PKG):set_feature("score.prompt_gravity", false)
OUT = {}
ok, err = pcall(prompt_fn); check(ok, "prompt with the feature off" .. (ok and "" or (" -- " .. tostring(err))))
check(#OUT == 0, "prompt untouched when the feature is off")
require(PKG):set_feature("score.prompt_gravity", true)

---------------------------------------------------------------------------
-- 6. Aliases
---------------------------------------------------------------------------
realprint("=== PHASE: aliases ===")
OUT = {}
ok, err = pcall(load("SC.API.Sheet:show()"))
check(ok, "SC show alias" .. (ok and "" or (" -- " .. tostring(err))))
check(output():find("PHY DAM", 1, true), "SC show prints the block on demand")

matches = { "SC features" }
ok, err = pcall(load_pkg_file("aliases/SC_feature.lua"))
check(ok, "SC features alias" .. (ok and "" or (" -- " .. tostring(err))))
matches = { "SC feature score.extras off", "score.extras", "off" }
ok, err = pcall(load_pkg_file("aliases/SC_feature_toggle.lua"))
check(ok, "SC feature toggle alias" .. (ok and "" or (" -- " .. tostring(err))))
check(require(PKG):feature("score.extras") == false, "feature toggled off")
require(PKG):set_feature("score.extras", true)
matches = { "SC" }
ok, err = pcall(load_pkg_file("aliases/SC_Help.lua"))
check(ok, "SC help alias" .. (ok and "" or (" -- " .. tostring(err))))

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
realprint("")
realprint(("=== RESULT: %d passed, %d failed ==="):format(passes, #failures))
for _, m in ipairs(failures) do realprint("  FAILED: " .. m) end
if #failures > 0 then error("harness failures", 0) end
