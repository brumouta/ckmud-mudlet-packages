-- MSDP: subscription, conversion, events, score fallbacks and reload seeding.
-- Run from the repo root: lua tests/MSDP_test.lua
local handlers, sent, events, now = {}, {}, {}, 5000
msdp = { KI = "800", UPDATE_EPOCH = "4990" }        -- values already there before the package loads
function getEpoch() return now end
function cecho(s) LOG = (LOG or "") .. s end
function sendMSDP(...) sent[#sent + 1] = table.concat({ ... }, " ") end
function registerNamedEventHandler(_, name, event, fn)
  handlers[event] = handlers[event] or {}
  handlers[event][name] = fn
end
function raiseEvent(event, ...)
  events[#events + 1] = { event, ... }
  for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end
end
unpack = unpack or table.unpack
local function server(name, value)             -- the server sends one variable
  msdp[name] = value
  raiseEvent("msdp." .. name)
end
local function lastEvent(name)
  for i = #events, 1, -1 do if events[i][1] == name then return events[i] end end
end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end

dofile("packages/MSDP/src/MSDP.lua")
ok(MSDP.Player.Ki == 800 and MSDP.ticked, "values already in msdp are picked up on load")
ok(lastEvent("MSDP.loaded") ~= nil, "MSDP.loaded is raised so other packages copy everything")
ok(handlers["msdp.KI"] and handlers["msdp.COMBO_HISTORY"] and handlers["msdp.CHARACTER_NAME"], "listens to the known variables")

-- Connect: ask for the server's list, and subscribe to the known variables meanwhile
sent = {}
raiseEvent("sysConnectionEvent")
ok(sent[1] == "LIST REPORTABLE_VARIABLES", "asks the server what it can report")
ok(sent[2]:match("^REPORT ") and sent[2]:find(" COMBO_HISTORY ") and sent[2]:find(" POWERLEVEL "), "subscribes to the known list")

-- The server's list arrives: subscribe to everything on it, including variables we don't know
sent = {}
server("REPORTABLE_VARIABLES", { "KI", "POWERLEVEL", "SHINY_NEW_THING" })
ok(sent[1]:find(" SHINY_NEW_THING") and sent[1]:find(" UPDATE_EPOCH") and sent[1]:find(" COMBO_HISTORY"),
   "subscribes to every reportable variable, plus the known ones")
server("SHINY_NEW_THING", "42")
ok(MSDP.raw.SHINY_NEW_THING == "42", "unknown variables are kept as-is in MSDP.raw")
sent = {}
MSDP:report()
ok(sent[2]:find(" SHINY_NEW_THING"), "later reports include the server's list")

-- Conversion and events
server("POWERLEVEL_MAX", "1,234,567")
ok(MSDP.Player.MaxPl == 1234567, "numbers are converted, commas and all")
local e = lastEvent("MSDP.changed")
ok(e[2] == "Player" and e[3] == "MaxPl" and e[4] == 1234567, "MSDP.changed says what changed")
server("STR", "50"); server("INT_BASE", "55")
ok(MSDP.Player.Stats.STR == 50 and MSDP.Player.BaseStats.INT == 55, "stats go to Stats / BaseStats")
server("ROOM_GRAVITY", "10"); server("OPPONENT_NAME", "Appule")
ok(MSDP.Room.Gravity == 10 and MSDP.Target.name == "Appule", "room and target values")
server("OPPONENT_NAME", "")
ok(MSDP.Target.name == "", "an empty opponent name is kept: it means no target")
server("CMD_STACK", "0")
ok(MSDP.cmd_stack == 0, "command stack")
server("COMBO_HISTORY", "deathbeam,death saucer")
ok(MSDP.Player.ComboHistory == "deathbeam,death saucer", "combo history kept as text")
server("UPDATE_EPOCH", "4998")
ok(lastEvent("MSDP.tick") ~= nil and MSDP:last_update() == 2, "server ticks raise MSDP.tick and drive last_update")

-- Name, race and base PL from score (the MUD doesn't send them any more)
MSDP.fromScore("name", "  Vorricer ")
MSDP.fromScore("race", "Human")
MSDP.fromScore("BasePl", "2,000,000")
ok(MSDP.Player.name == "Vorricer" and MSDP.Player.race == "Human" and MSDP.Player.BasePl == 2000000,
   "name, race and base PL come from the score sheet")
server("CHARACTER_NAME", "")
ok(MSDP.Player.name == "Vorricer", "an empty CHARACTER_NAME from the server is ignored")
server("CHARACTER_NAME", "Vorrac")
ok(MSDP.Player.name == "Vorrac", "if the server sends CHARACTER_NAME again, it wins")
MSDP.fromScore("name", "Someoneelse")
ok(MSDP.Player.name == "Vorrac", "and score no longer overrides it")

-- Reload: the new copy of the package replays what's there
events = {}
dofile("packages/MSDP/src/MSDP.lua")
ok(MSDP.Player.MaxPl == 1234567 and lastEvent("MSDP.loaded"), "reload keeps values and tells the packages")

MSDP.command("help"); MSDP.command("status"); MSDP.command("show"); MSDP.command("bogus")
ok(LOG:find("Last update: 2s ago") and LOG:find("Name: Vorrac"), "msdp status")
print("\nMSDP: ALL PASSED")
