-- dl2: event gate, boss chain, rivals (including group rivals) and the dl2 command.
-- Run from the repo root: lua tests/DataLords2_test.lua
local sent, enabled, timers, temps, id = {}, {}, {}, {}, 0
-- Like the real MUD since July 2026: MSDP does not send CHARACTER_NAME
msdp = {}
local handlers, saved, clock = {}, {}, 1000
os.time = function() return clock end
function getMudletHomeDir() return "/profile" end
local function copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = copy(x) end
  return c
end
function table.save(path, t) saved[path] = copy(t) end      -- like Mudlet: a snapshot on disk
function table.load(path, t) if not saved[path] then error("no file") end; for k, v in pairs(copy(saved[path])) do t[k] = v end end
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function enableTrigger(n) enabled[n] = true end
function disableTrigger(n) enabled[n] = false end
function tempTimer(d, f) id = id + 1; timers[id] = { d = d, f = f }; return id end
function killTimer(i) timers[i] = nil end
local lastRegex
function tempRegexTrigger(p, f)
  id = id + 1; temps[id] = { p = p, f = f }
  if p:find("Location", 1, true) then lastRegex = id end    -- the `event` reply trigger
  return id
end
local function here()                               -- no "not here" answer: the look's wait runs out
  local tm = dl2.lookTimer and timers[dl2.lookTimer]
  if tm then timers[dl2.lookTimer] = nil; tm.f() end
end
local function looked(line)                         -- the MUD's answer to `look <npc>`
  for _, tm in pairs(temps) do
    local name = (tm.p == dl2.IS_HERE) and line:match("^(.-) is in .+ condition%.$")
    if name then matches = { line, name }; tm.f() end
  end
end
local function notHere()                            -- the MUD answers `look <npc>` with "not here"
  for i, tm in pairs(temps) do if tm.p == dl2.NOT_HERE then tm.f(); return end end
  error("nobody is waiting for a look answer")
end
function killTrigger(i) temps[i] = nil end
function sendMSDP(...) sent[#sent + 1] = "MSDP " .. table.concat({ ... }, " ") end
function registerNamedEventHandler(_, name, event, fn) handlers[event .. ":" .. name] = fn end
local namedTimers = {}
function registerNamedTimer(_, name, _, fn) namedTimers[name] = fn end
function raiseEvent(event, ...)
  for key, fn in pairs(handlers) do
    if key:sub(1, #event + 1) == event .. ":" then fn(event, ...) end
  end
end
function getEpoch() return clock end
local function typed(cmd) handlers["sysDataSendRequest:own request"]("sysDataSendRequest", cmd) end
local function flush(upTo)                          -- run the timers that are due now (snapshot first:
  upTo = upTo or 9                                    -- a timer may start another one); the 10-second
  local due = {}                                      -- checks only run with later()
  for i, tm in pairs(timers) do if tm.d <= upTo then due[#due + 1] = { i, tm.f } end end
  table.sort(due, function(a, b) return a[1] < b[1] end)
  for _, d in ipairs(due) do timers[d[1]] = nil; d[2]() end
end
local function later() flush(math.huge) end
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
typed("request event 18"); clock = clock + 5
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
temps[lastRegex].f(); here()
expect("focus 'instant' joe | look joe | fly | fly | pursue jhet | sense jhet | ss macub")
dl2.attackBoss("macub"); expect("pursue jhet | sense jhet | ss macub")

-- A rival pauses the event; another mob dying doesn't resume it; the rival dying does
dl2.rivalAppears("Capella", "you"); assert(enabled["dl2 Bosses"] and enabled["dl2 Rival dies"])   -- boss lines still recorded
expect("ss Capella | ss Capella | ss Capella | ss Capella")
dl2.rivalDies("Jhet 2.0"); expect("")
dl2.rivalDies("Capella the Saiba"); expect("get all"); flush()
assert(enabled["dl2 Bosses"] and not enabled["dl2 Rival dies"])
expect("pursue jhet | sense jhet | ss macub")

-- Group rival plus a second rival: resume only when both are dead
dl2.rivalAppears("Capella", "Bob"); expect("ss Capella | ss Capella | ss Capella | ss Capella")
dl2.rivalAppears("Laser", "you"); expect("ss Laser | ss Laser | ss Laser | ss Laser")
dl2.rivalAppears("Laser", "you"); expect("")                    -- same rival again: no extra volley
dl2.rivalDies("Capella the Saiba"); expect("get all | ss Laser")
flush(); assert(next(dl2.rivals)); expect("")          -- still paused: no boss attack yet
dl2.rivalDies("Laser the Android"); expect("get all"); flush()
assert(enabled["dl2 Bosses"]); expect("pursue jhet | sense jhet | ss macub")

-- dl2 resume clears a rival that never died
dl2.rivalAppears("Nappa", "you"); expect("ss Nappa | ss Nappa | ss Nappa | ss Nappa")
dl2.command("resume"); assert(enabled["dl2 Bosses"] and not next(dl2.rivals))
expect("event")                                       -- looks the boss up again and travels

-- Boss chain and the loop
dl2.bossDied("zenzeyh"); expect("get all.tab | pursue zenzeyh | sense zenzeyh | ss zenzeyh")
dl2.command("loop", "off"); dl2.zenzeyhDied(); flush(); expect("get all.tab")          -- loop off: just the tab
dl2.requested("technine"); sent = {}                                                  -- the next event
dl2.command("loop", "on"); dl2.zenzeyhDied(); flush(); expect("get all.tab | request event 18")

-- After the event ends, rivals are ignored
dl2.ended(); dl2.rivalAppears("Capella", "you"); expect("")
dl2.command("attack", "kame"); dl2.attackBoss("x"); expect("pursue x | sense x | kame x")
-- Jhet and Macubyree fight together and die in either order
local function arrive()                              -- the `event` reply: travel and attack Jhet
  matches = { "Location: Earth   Time Rem: 60 mins", "Earth" }
  temps[lastRegex].f(); here()
end
dl2.command("attack", "ss"); dl2.requested("technine"); sent = {}     -- our event is running
dl2.startPair(); arrive()
expect("event | focus 'instant' malak | look malak | pursue jhet | sense jhet | ss macub")
dl2.pairDied("macub"); expect("look jhet"); here(); expect("ss jhet")                                  -- usual order: then Jhet, no pursue
dl2.pairDied("jhet"); expect("")                                           -- both down: wait for the next boss
assert(dl2.boss == nil and LOG:find("are down"))
print("OK  Macubyree first, then Jhet (same room, no pursue)")

dl2.requested("technine"); dl2.startPair(); arrive(); sent = {}
dl2.pairDied("jhet"); expect("")                     -- someone kills Jhet first: Macubyree dies with him
assert(dl2.boss == nil and dl2.dead.macub and LOG:find("Jhet and Macubyree are down %- waiting for Weezpurr"))
dl2.goTo("weezp"); expect("event")                   -- Weezpurr's start line: off we go
dl2.pairDied("macub"); expect("")
print("OK  Jhet killed first: the pair is done, goes to Weezpurr on her start line")



dl2.requested("technine"); dl2.startPair(); arrive(); sent = {}
dl2.pairDied("macub"); expect("look jhet"); here(); expect("ss jhet")
dl2.pairDied("macub"); expect("")                    -- a repeated line doesn't restart the chase
print("OK  a new pair starts fresh; repeats are ignored")

-- The MSDP target is ignored: it can keep an old opponent long after the fight
sent, LOG = {}, ""
MSDP.set("Target", "name", "Zenzeyh v2.0")          -- left over from the last event
dl2.requested("technine"); dl2.startPair(); expect("event")
assert(not LOG:find("once"))
print("OK  a stale MSDP target right after the request doesn't hold the travel back")
MSDP.set("Target", "name", "")
arrive(); sent = {}

dl2.goTo("phenix"); expect("event")                 -- not busy: straight away
print("OK  announced while free: straight away")

-- Rivals no longer hide boss lines: whatever happened meanwhile is picked up after
dl2.rivalAppears("Capella", "you"); sent = {}
dl2.goTo("weezp"); expect("")                       -- start line during a rival: queued
dl2.rivalDies("Capella the Saiba"); expect("get all"); flush(); flush()
expect("event")                                     -- the rival's gone: off to Weezpurr
dl2.rivalAppears("Capella", "you"); sent = {}
dl2.bossDied("daiue"); expect("get all.tab")        -- Phenix died during the rival: loot, but don't chase yet
dl2.rivalDies("Capella the Saiba"); flush()
expect("get all | pursue daiue | sense daiue | ss daiue")
print("OK  boss lines during a rival are kept and acted on afterwards")

-- Safety net: a queued boss is also picked up by the 5-second check
dl2.rivalAppears("Capella", "you"); dl2.goTo("weezp"); sent = {}
dl2.rivals = {}                                     -- the rival vanished without a death line
namedTimers["pending check"](); flush(); expect("event")
print("OK  the periodic check catches a missed signal")

-- A missed Jhet/Macubyree death line doesn't block: Weezpurr's start line proves they're done
local function arriveAt(planet)
  matches = { "Location: " .. planet .. "   Time Rem: 60 mins", planet }
  temps[lastRegex].f(); here()
end
timers = {}; MSDP.Target.name = ""
dl2.requested("technine"); dl2.startPair(); arriveAt("Earth"); sent = {}
dl2.pairDied("macub"); sent = {}                    -- Jhet's death line never seen
dl2.goTo("weezp"); expect("event")
print("OK  Weezpurr goes even if a pair death line was missed")

-- A fight refuses the instant: "You do not see that here." -> travel again 3 seconds later
timers = {}; LOG = ""
dl2.goTo("phenix"); matches = { "Location: Vegeta   Time Rem: 60 mins", "Vegeta" }; temps[lastRegex].f()
expect("event | focus 'instant' gine | look gine")
notHere(); expect("")                               -- waits a moment...
assert(LOG:find("travelling again in 3s %(try 1/5%)"))
flush(); expect("event")                            -- ...then looks it up again
print("OK  a refused instant is tried again after 3 seconds")

-- Did `focus 'instant'` work? After attacking, the boss must be my target; otherwise travel again
timers = {}; MSDP.set("Target", "name", ""); LOG = ""
dl2.goTo("weezp"); arriveAt("Namek"); expect("event | focus 'instant' dende | look dende | pursue weezp | sense weezp | ss weezp")
later(); flush(); expect("event")                   -- not my target 10s later: look it up again
assert(LOG:find("weezp isn't my target %- travelling again in 3s %(try 1/5%)"))
arriveAt("Namek"); sent = {}
MSDP.set("Target", "name", "Weezpurr v2.0")         -- this time it worked
later(); expect("")
print("OK  a failed instant is retried; a successful one isn't")

timers = {}; MSDP.set("Target", "name", "")
dl2.goTo("phenix"); arriveAt("Vegeta"); sent = {}
for _ = 1, dl2.MAX_TRIES do later(); flush(); arriveAt("Vegeta") end; sent = {}
later(); flush(); expect("")                        -- gives up after 5 tries, says how to retry
assert(LOG:find("giving up"))
dl2.command("resume"); expect("event")              -- dl2 resume travels again
print("OK  gives up after " .. dl2.MAX_TRIES .. " tries; dl2 resume travels again")

timers = {}
dl2.goTo("weezp"); arriveAt("Namek"); sent = {}
dl2.bossDead("Weezpurr"); expect("get all.tab")    -- killed before the check: loot
later(); expect("")
dl2.goTo("phenix"); sent = {}; later(); flush(); expect("event")   -- `event` never answered: asked again
print("OK  no retry for a dead boss; an unanswered `event` is asked again")

-- Jhet dies, Macubyree's death is seen: nothing ever pursues Macubyree again
timers = {}; MSDP.set("Target", "name", ""); dl2.requested("technine")
dl2.startPair(); arriveAt("Earth"); sent = {}
dl2.bossDead("Macubyree"); expect("get all.tab | look jhet"); here(); expect("ss jhet")   -- loot, then Jhet
dl2.bossDead("Jhet"); expect("get all.tab"); assert(dl2.boss == nil)
later(); expect("")                                 -- no retry: he's dead
dl2.attackBoss("macub"); dl2.engage("macub"); dl2.findAndAttack("macub"); dl2.command("resume"); later()
expect("")
print("OK  a dead Macubyree is never pursued again")
dl2.startPair(); expect("")                          -- the start shout again: the pair stays dead
assert(dl2.targeting("weezp") == false)
MSDP.set("Target", "name", "Macubyree demonspawn"); assert(not dl2.targeting("macub"))
MSDP.set("Target", "name", "Macubyree"); assert(dl2.targeting("macub"))
MSDP.set("Target", "name", "Weezpurr v2.0"); assert(dl2.targeting("weezp"))
MSDP.set("Target", "name", "Jhet 2.0"); assert(dl2.targeting("jhet"))
MSDP.set("Target", "name", "")
print("OK  Macubyree demonspawn is not Macubyree; a repeated start shout is ignored")

-- He dies between asking `event` and its answer: no travel
dl2.requested("technine"); timers = {}; sent = {}
dl2.startPair(); sent = {}; dl2.bossDead("Jhet"); sent = {}; arriveAt("Earth"); expect("")   -- Jhet dead: pair done, no travel
dl2.goTo("weezp"); dl2.bossDead("Weezpurr"); sent = {}; arriveAt("Namek"); expect("")
print("OK  bosses that die during the lookup aren't travelled to")

-- The whole event, as it should go
do
  timers, sent, LOG = {}, {}, ""
  local function at(planet) matches = { "Location: " .. planet .. "   Time Rem: 60 mins", planet }; temps[lastRegex].f() end
  dl2.command("limit", "off"); dl2.command("loop", "on")
  typed("request event 18"); dl2.requested("technine"); expect("")                 -- my request: everything ON
  dl2.startPair(); expect("event"); at("Earth")                                     -- Macubyree's shout
  expect("focus 'instant' malak | look malak")                                      -- did the instant work?
  notHere(); flush(); expect("event")                                                        -- no malak here: it didn't, again
  at("Earth"); expect("focus 'instant' malak | look malak"); here()
  expect("pursue jhet | sense jhet | ss macub")                                     -- pursue Jhet, attack Macubyree
  dl2.bossDead("Macubyree"); expect("get all.tab | look jhet")                     -- loot, is Jhet here?
  notHere(); expect("pursue jhet | ss jhet")                                        -- not here: pursue him first
  dl2.bossDead("Jhet"); expect("get all.tab")
  dl2.goTo("weezp"); expect("event"); at("Namek"); here()                           -- Weezpurr's shout
  expect("focus 'instant' dende | look dende | pursue weezp | sense weezp | ss weezp")
  dl2.bossDead("Weezpurr"); expect("get all.tab")
  dl2.goTo("phenix"); expect("event"); at("Vegeta"); here()
  expect("focus 'instant' gine | look gine | pursue phenix | sense phenix | ss phenix")
  dl2.bossDead("Phenix"); dl2.bossDied("daiue"); expect("get all.tab | pursue daiue | sense daiue | ss daiue")
  dl2.bossDead("Daiue"); dl2.bossDied("zenzeyh"); expect("get all.tab | pursue zenzeyh | sense zenzeyh | ss zenzeyh")
  dl2.ended(); timers = {}; dl2.zenzeyhDied(); expect("get all.tab")
  assert(LOG:find("Re%-requesting the event in 5s"))
  flush(); expect("request event 18")                                               -- 5 seconds later
  dl2.eventBusy(); flush(); expect("request event 18")                              -- another event running: again
  dl2.eventBusy(); flush(); expect("request event 18")
  dl2.requested("technine"); dl2.eventBusy(); flush(); expect("")                   -- it went through: stop retrying
  print("OK  the whole event: request, pair, Weezpurr, Phenix, Daiue, Zenzeyh, loot each, loop")
  dl2.command("loop", "off"); dl2.requested("technine"); timers, sent = {}, {}
  for planet, route in pairs(dl2.travel) do                                         -- every planet's instant is checked
    local npc = route[1]:match("^focus 'instant' (%S+)")
    dl2.tries = 0; dl2.findAndAttack("weezp"); at(planet)
    expect("event | " .. route[1] .. " | look " .. npc)
    notHere(); flush(); expect("event")                                                      -- failed: travel again
    at(planet); here(); sent = {}; timers = {}
  end
  print("OK  the instant is checked on every planet (malak, dende, gine, innkeeper, minotia, joe)")
  dl2.tries = 0; dl2.findAndAttack("phenix"); at("Vegeta"); sent = {}
  looked("Malak is in excellent condition."); expect("")                           -- someone else: keep waiting
  looked("Gine is in excellent condition."); expect("pursue phenix | sense phenix | ss phenix")   -- straight on
  assert(dl2.lookTimer == nil)
  print("OK  \"Gine is in excellent condition.\" confirms the instant at once")
  timers = {}
  dl2.requested("technine"); dl2.eventBusy(); flush(); expect("")                   -- loop off: not ours to retry
  timers = {}
end
timers = {}; MSDP.set("Target", "name", "")
timers = {}; MSDP.set("Target", "name", "")

-- Zenzeyh's last words ("[RAID: Zenzeyh v2.0] Power creep is real...") end the event and
-- switch the boss folder off just BEFORE his "is dead!" line. The death trigger must
-- therefore live outside that folder, and still act for an event that just ended.
do
  local f = io.open("packages/DataLords2/package.json"); local pj = f:read("a"); f:close()
  local killedAt = pj:find('"name": "dl2 Killed Zenzeyh"', 1, true)
  local bossesAt = pj:find('"name": "dl2 Bosses"', 1, true)
  assert(killedAt and bossesAt and killedAt < bossesAt, "Killed Zenzeyh must not be inside the dl2 Bosses folder")
end
dl2.command("tokens", "reset"); dl2.command("limit", "off"); dl2.command("loop", "on"); sent = {}
dl2.requested("technine"); sent = {}
dl2.ended()                                         -- last words first...
assert(enabled["dl2 Bosses"] == false)
dl2.zenzeyhDied(); flush()                          -- ...then the death line
expect("get all.tab | request event 18")
print("OK  last words before the death line: tab grabbed, next event requested")

dl2.requested("technine"); sent = {}
dl2.zenzeyhDied(); flush()                          -- death line first...
dl2.ended(); dl2.zenzeyhDied(); flush()             -- ...then last words (and a stray repeat)
expect("get all.tab | request event 18")
print("OK  death line before the last words: still exactly one request")

dl2.requested("Bob"); sent = {}                     -- someone else's event
dl2.ended(); dl2.zenzeyhDied(); flush(); expect("")
dl2.requested("technine"); dl2.ended(); clock = clock + 61; sent = {}
dl2.zenzeyhDied(); flush(); expect("")              -- too long after our event ended
print("OK  ignored for other players' events, and long after ours ended")
dl2.command("limit", "100000"); dl2.command("loop", "off")   -- back to the defaults for the next section

-- Token spending: 10,000 per event you request, one session per connection
LOG, sent = "", {}
dl2.command("tokens", "reset")
assert(dl2.session.spent == 0 and dl2.tokenLimit == 100000)
dl2.command("limit", "30k"); assert(dl2.tokenLimit == 30000 and LOG:find("Session token limit: 30,000 %(3 events%)"))
dl2.command("loop", "on"); assert(dl2.loop)
dl2.requested("technine"); assert(dl2.session.spent == 10000 and dl2.session.events == 1)
assert(LOG:find("Event cost 10,000 tokens %- this session: 10,000 of 30,000"))
dl2.requested("Bob"); assert(dl2.session.spent == 10000)           -- someone else's event costs you nothing
dl2.requested("technine"); dl2.zenzeyhDied(); flush()
assert(sent[#sent] == "request event 18")                               -- 20,000 spent: the loop re-requests
dl2.requested("technine"); assert(dl2.session.spent == 30000)
assert(not dl2.loop and LOG:find("Session token limit reached %(30,000 of 30,000 spent%)"))
sent = {}
dl2.zenzeyhDied(); flush(); assert(table.concat(sent, " | ") == "get all.tab")   -- still loots, no fourth request
LOG = ""
dl2.command("loop", "on"); assert(not dl2.loop and LOG:find("Loop stays OFF"))
print("OK  loop stops at the session token limit")

-- Saved: a reload of the package keeps the session's spending
dofile("packages/DataLords2/src/DataLords2.lua"); sent = {}
assert(dl2.session.spent == 30000 and dl2.tokenLimit == 30000)
print("OK  spending survives a reload")

-- A new connection starts a new session; the old one goes into the history
handlers["sysConnectionEvent:new session"]("sysConnectionEvent")
assert(dl2.session.spent == 0 and dl2.history[1].spent == 30000 and dl2.history[1].events == 3)
LOG = ""; dl2.command("tokens")
assert(LOG:find("This session") and LOG:find("30,000 tokens, 3 events"))
print("OK  new session per connection, old one kept in history")

-- Your token balance (MSDP) also stops the loop
MSDP.Player.Tokens = 5000
LOG = ""; dl2.command("loop", "on"); assert(not dl2.loop and LOG:find("Only 5,000 tokens left"))
MSDP.Player.Tokens = nil
print("OK  too few tokens left stops the loop")

-- Limit forms
assert(dl2.parseTokens("200k") == 200000 and dl2.parseTokens("1.5m") == 1500000 and dl2.parseTokens("200,000") == 200000)
assert(dl2.parseTokens("lots") == nil)
LOG = ""; dl2.command("limit", "lots"); assert(LOG:find("Didn't understand 'lots'") and dl2.tokenLimit == 30000)
dl2.command("limit", "off"); assert(dl2.tokenLimit == false)
dl2.command("loop", "on"); assert(dl2.loop)                         -- no limit: loop allowed
dofile("packages/DataLords2/src/DataLords2.lua"); sent = {}
assert(dl2.tokenLimit == false)                                      -- "off" is saved too
print("OK  limit accepts 200k / 1.5m / 200,000 / off")

dl2.command("help"); dl2.command("status"); dl2.command("bogus")
print("\ndl2: ALL PASSED")
