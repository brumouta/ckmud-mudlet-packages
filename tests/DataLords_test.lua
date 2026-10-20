-- dl2: event gate, boss chain, rivals (including group rivals) and the dl2 command.
-- Run from the repo root: lua tests/DataLords_test.lua
local sent, enabled, timers, temps, id = {}, {}, {}, {}, 0
msdp = { CHARACTER_NAME = "Technine" }
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
function registerNamedEventHandler() end
local function flush() for i, f in pairs(timers) do timers[i] = nil; f() end end
local function expect(want)
  local got = table.concat(sent, " | "); sent = {}
  assert(got == want, "\n got: " .. got .. "\nwant: " .. want)
  print("OK  " .. (want == "" and "(nothing)" or want))
end

dofile("packages/DataLords/src/DataLords.lua")
expect("MSDP REPORT CHARACTER_NAME COMBO_HISTORY")

-- Only my own request turns the bosses on
dl2.requested("Bob"); assert(not dl2.active and enabled["dl2 Bosses"] == false)
dl2.requested("technine"); assert(dl2.active and enabled["dl2 Bosses"])

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
