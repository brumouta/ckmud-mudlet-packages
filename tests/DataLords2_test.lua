-- dl2: event gate, boss chain, rivals (including group rivals) and the dl2 command.
-- Run from the repo root: lua tests/DataLords2_test.lua
local sent, enabled, timers, temps, id = {}, {}, {}, {}, 0
-- Like the real MUD since July 2026: MSDP does not send CHARACTER_NAME
msdp = {}
local handlers, saved, clock = {}, {}, 1000
os.time = function() return clock end
function getMudletHomeDir() return "/profile" end
function table.save(path, t) saved[path] = { name = t.name } end
function table.load(path, t) if not saved[path] then error("no file") end; for k, v in pairs(saved[path]) do t[k] = v end end
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function enableTrigger(n) enabled[n] = true end
function disableTrigger(n) enabled[n] = false end
function tempTimer(_, f) id = id + 1; timers[id] = f; return id end
function killTimer(i) timers[i] = nil end
local lastRegex
function tempRegexTrigger(_, f) id = id + 1; temps[id] = f; lastRegex = id; return id end
function killTrigger(i) temps[i] = nil end
function sendMSDP(...) sent[#sent + 1] = "MSDP " .. table.concat({ ... }, " ") end
function registerNamedEventHandler(_, name, event, fn) handlers[event .. ":" .. name] = fn end
function raiseEvent(event, ...)
  for key, fn in pairs(handlers) do
    if key:sub(1, #event + 1) == event .. ":" then fn(event, ...) end
  end
end
function getEpoch() return clock end
local function typed(cmd) handlers["sysDataSendRequest:own request"]("sysDataSendRequest", cmd) end
local function flush() for i, f in pairs(timers) do timers[i] = nil; f() end end
local function expect(want)
  local got = table.concat(sent, " | "); sent = {}
  assert(got == want, "\n got: " .. got .. "\nwant: " .. want)
  print("OK  " .. (want == "" and "(nothing)" or want))
end

-- The shared MSDP package is installed alongside, as it must be
dofile("packages/MSDP/src/MSDP.lua")
dofile("packages/DataLords2/src/DataLords2.lua")
expect("")                                               -- subscribing is the MSDP package's job now

-- Name unknown: someone else's request stays off and says how to fix it
dl2.requested("Bob"); assert(not dl2.active and enabled["dl2 Bosses"] == false)
assert(LOG:find("I don't know your name yet"))

-- Requesting it yourself teaches the bot your name (and it's saved)
typed("req event 18"); clock = clock + 5
dl2.requested("Technine"); assert(dl2.active and enabled["dl2 Bosses"] and dl2.name == "Technine")
assert(saved["/profile/DataLords2.lua"].name == "Technine")
print("OK  learned the name from my own request")

-- A request long after mine is not assumed to be mine
dl2.name = nil; saved = {}
typed("req event 18"); clock = clock + 60
dl2.requested("Bob"); assert(not dl2.active and dl2.name == nil)

-- The MSDP package's name (from score, or from the server) is used, and beats a saved one
MSDP.fromScore("name", "Technine")
assert(select(2, dl2.myName()) == "MSDP")
dl2.requested("Bob"); assert(not dl2.active)
dl2.requested("technine"); assert(dl2.active)
dl2.setName("Oldalt")
assert(dl2.myName() == "Technine")
MSDP.Player.name = nil
assert(dl2.myName() == "Oldalt")                         -- saved name only until MSDP knows yours
print("OK  name comes from the MSDP package first")

-- Without the MSDP package installed it says so instead of failing quietly
local shared = MSDP; MSDP = nil
dl2.checkMSDP(); assert(LOG:find("DataLords2 needs the MSDP package"))
MSDP = shared
print("OK  missing MSDP package is reported")

-- dl2 name sets it, and it survives a reload of the script
dl2.command("name", "Technine"); dl2.name = nil
dofile("packages/DataLords2/src/DataLords2.lua"); sent = {}
assert(dl2.name == "Technine")
dl2.requested("technine"); assert(dl2.active and enabled["dl2 Bosses"])
print("OK  saved name survives a reload")

-- Location lookup, then travel and attack
dl2.findAndAttack("jhet"); expect("event")
matches = { "Location: Otherworld   Time Rem: 60 mins", "Otherworld" }
temps[lastRegex]()
expect("focus 'instant' joe | fly | fly | pursue jhet | sense jhet | ss jhet")
dl2.attackBoss("macub"); expect("pursue macub | sense macub | ss macub")

-- A rival pauses the event; another mob dying doesn't resume it; the rival dying does
dl2.rivalAppears("Capella", "you"); assert(enabled["dl2 Bosses"] == false and enabled["dl2 Rival dies"])
expect("ss Capella | ss Capella | ss Capella | ss Capella")
dl2.rivalDies("Jhet 2.0"); expect("")
dl2.rivalDies("Capella the Saiba"); expect("get all"); flush()
assert(enabled["dl2 Bosses"] and not enabled["dl2 Rival dies"])
expect("pursue macub | sense macub | ss macub")

-- Group rival plus a second rival: resume only when both are dead
dl2.rivalAppears("Capella", "Bob"); expect("ss Capella | ss Capella | ss Capella | ss Capella")
dl2.rivalAppears("Laser", "you"); expect("ss Laser | ss Laser | ss Laser | ss Laser")
dl2.rivalAppears("Laser", "you"); expect("")                    -- same rival again: no extra volley
dl2.rivalDies("Capella the Saiba"); expect("get all | ss Laser")
flush(); assert(enabled["dl2 Bosses"] == false); expect("")
dl2.rivalDies("Laser the Android"); expect("get all"); flush()
assert(enabled["dl2 Bosses"]); expect("pursue macub | sense macub | ss macub")

-- dl2 resume clears a rival that never died
dl2.rivalAppears("Nappa", "you"); expect("ss Nappa | ss Nappa | ss Nappa | ss Nappa")
dl2.command("resume"); assert(enabled["dl2 Bosses"] and not next(dl2.rivals))
expect("pursue macub | sense macub | ss macub")

-- Boss chain and the loop
dl2.bossDied("zenzeyh"); expect("get all.tab | pursue zenzeyh | sense zenzeyh | ss zenzeyh")
dl2.command("loop", "on"); dl2.zenzeyhDied(); flush(); expect("get all.tab | req event 18")

-- After the event ends, rivals are ignored
dl2.ended(); dl2.rivalAppears("Capella", "you"); expect("")
dl2.command("attack", "kame"); dl2.attackBoss("x"); expect("pursue x | sense x | kame x")
dl2.command("help"); dl2.command("status"); dl2.command("bogus")
print("\ndl2: ALL PASSED")
