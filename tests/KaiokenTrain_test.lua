-- kt: KaiokenTrain. Run from the repo root: lua tests/KaiokenTrain_test.lua
local id, timers, sent, out, saved = 0, {}, {}, "", nil
function send(c) sent[#sent + 1] = c end
function cecho(s) out = out .. s end
function tempTimer(_, f, rep) id = id + 1; timers[id] = { f = f, rep = rep }; return id end
function killTimer(i) if i then timers[i] = nil end end
function getConnectionInfo() return "host", 1, true end
function getMudletHomeDir() return "/nonexistent-kt-test" end
local handlers = {}
function registerNamedEventHandler(_, name, event, f) handlers[event .. ":" .. name] = f end
local gagged = 0
function deleteLine() gagged = gagged + 1 end
table.save = function(_, t) saved = t end

MSDP = { Player = { Fatigue = 900, MaxFatigue = 1000, Thirst = 80, GK = 10, MaxGK = 10, Ki = 5, MaxKi = 5,
                    Pl = 100, MaxPl = 100 } }
local P = MSDP.Player

local function ok(c, what) assert(c, what); print("OK  " .. what) end
local function has(cmd) for _, c in ipairs(sent) do if c == cmd then return true end end end
local function tick() sent = {}; kt.tick() end
local function prompt(cur, mastery)
  if cur then kt.line(string.format("[Kaioken: %d/%d ]", cur, mastery)) end
  kt.line("[Pl: 4,320 | Ki: 100% | Fat: 90%] [HT][42583/42583x G]")
end

dofile("packages/KaiokenTrain/src/KaiokenTrain.lua")

-- ---- reading the game
prompt(5, 10)
ok(kt.kaioken == 5 and kt.mastery == 10, "reads kaioken and mastery from the prompt")
prompt()
ok(kt.kaioken == 0, "kaioken is 0 when the prompt has no [Kaioken] line")
kt.line("You have mastered kaioken x12.")
ok(kt.mastery == 12, "reads mastery from status")
kt.line("Syntax: Kaioken 1-120")
ok(gagged == 0 and kt.max == 120, "leaves getmax replies alone while not training")

-- ---- start
sent = {}
kt.command("start")
ok(kt.on and has("kaioken getmax") and has("status") and kt.mastery == nil, "start asks getmax and status, forgets old mastery")
ok(next(timers) ~= nil, "start runs the loop")
tick()
ok(#sent == 0 and kt.on, "waits while mastery is unknown")
kt.line("Syntax: Kaioken 1-120")
ok(kt.max == 120 and gagged == 1, "reads and hides the getmax reply")

-- ---- raise / no drinking / rest / wake
prompt(5, 10)
tick()
ok(has("kaioken 21"), "raises kaioken to mastery + 11 by default")
prompt(21, 10); P.Thirst = 30
tick()
for _, c in ipairs(sent) do assert(not c:find("^drink"), "drank: " .. c) end
ok(true, "never drinks, even when thirsty")
P.Thirst = 80; P.Fatigue = 100
tick()
ok(has("kaioken") and sent[#sent] == "sleep" and sent[#sent - 1] == "land" and kt.resting, "drops kaioken, lands and sleeps when fatigued")
tick()
ok(#sent == 0, "stays asleep until rested")
P.Fatigue = 1000
tick()
ok(has("wake") and not kt.resting, "wakes when rested")

-- ---- completion waits for a fresh getmax
prompt(112, 112)
tick()
ok(has("kaioken getmax") and kt.on, "at the goal it re-checks the ceiling before stopping")
kt.line("Syntax: Kaioken 1-120")
tick()
ok(has("kaioken 112") and not kt.on and next(timers) == nil, "stops once the ceiling is confirmed")

-- ---- a ceiling that grew keeps it training
kt.command("start"); kt.line("Syntax: Kaioken 1-40")
prompt(0, 24); tick()
ok(has("kaioken 35"), "trains at mastery + 11 under a ceiling of 40")
prompt(35, 32); tick()
ok(has("kaioken getmax") and kt.on, "at a possibly stale goal it asks again")
kt.line("Syntax: Kaioken 1-48")
tick()
ok(kt.max == 48 and kt.on and has("kaioken 43"), "the ceiling grew: training goes on")
kt.command("stop")
ok(not kt.on and next(timers) == nil, "stop")

-- ---- already mastered
kt.command("start"); kt.line("Syntax: Kaioken 1-40"); prompt(0, 32); kt.line("Syntax: Kaioken 1-40")
tick()
ok(not kt.on, "stops straight away when already mastered")

-- ---- room for Accelerated Mastery
kt.command("start"); kt.line("Syntax: Kaioken 1-128")
prompt(0, 20); tick()
ok(has("kaioken 31"), "room 2: mastery + 11")
kt.command("room", "0")
ok(saved.room == 0, "room saved")
tick()
ok(has("kaioken 29"), "room 0: mastery + 9")
kt.command("room", "3")
for _ = 1, 3 do tick() end
ok(has("kaioken 32"), "asked for mastery + 12 three times")
tick()
ok(has("kaioken 31"), "steps down when the level doesn't hold")
tick()
ok(has("kaioken 31") and not has("kaioken 32"), "remembers the lower room")
prompt(31, 23); tick()
ok(has("kaioken 34"), "follows a 3-point gain with the same room")
prompt(34, 23); tick()
ok(kt.asked == nil, "reaching the level clears the pending ask")
kt.command("room", "2")

-- ---- the last stretch trains at the ceiling itself
local seen = {}
kt.roomCap = 0   -- an earlier step-down must not hold it back now
for m = 117, 119 do prompt(0, m); tick(); for _, c in ipairs(sent) do seen[c] = true end end
ok(seen["kaioken 128"] and not seen["kaioken 127"] and not seen["kaioken 125"], "near the top: always kaioken 128, never steps down")
prompt(0, 120); tick()
ok(has("kaioken getmax"), "mastery 120 (128 - 8): checks the ceiling before stopping")
kt.line("Syntax: Kaioken 1-128"); tick()
ok(has("kaioken 120") and not kt.on, "mastered at 120: stops")

-- ---- waits for a prompt and for MSDP
kt.command("start")
handlers["sysDisconnectionEvent:kt disconnect"]()
prompt(0, 5); kt.prompted = false
tick()
ok(#sent == 0, "does nothing before a prompt after (re)connecting")
prompt(0, 5)
local saveP = MSDP; MSDP = nil
tick(); tick(); out = ""; tick()
ok(#sent == 0 and out:find("needs the MSDP package"), "without MSDP it waits and says so")
MSDP = saveP
tick()
ok(has("kaioken 16"), "mastery 5: trains at 5 + 9 + 2 = 16")

-- ---- prompt overlay, status, help, toggle
out = ""; prompt(16, 5)
ok(out:find("kt training") and out:find("x16 / x5"), "shows the bot state on the prompt while training")
out = ""; kt.command("status")
ok(out:find("training") and out:find("mastery x5") and out:find("ceiling x128"), "status")
out = ""; kt.command()
ok(out:find("kt start") and out:find("kt room"), "help lists the commands")
-- ---- Gumshoe's gum repeat
gum = { rep = {} }
local function starting() handlers["gumshoe.repeat.starting:kt gumshoe starting"]() end
local function done() gum.rep.claimed = nil; handlers["gumshoe.repeat.done:kt gumshoe done"]() end
sent = {}; out = ""; kt.command("start"); P.Fatigue = 1000
starting()
ok(not kt.on and next(timers) == nil and has("kaioken") and not has("wake"), "a case pauses training and drops kaioken")
ok(out:find("No way back from Jaco"), "says training stays off without kt back")
sent = {}; done()
ok(not kt.on and gum.rep.claimed == nil and #sent == 0, "without kt back it stays off after the case")

kt.command("back", "crecall; w")
ok(saved.back == "crecall; w", "kt back saved")
kt.command("start"); kt.resting = true
sent = {}; starting()
ok(has("wake") and not kt.on, "asleep when the case starts: wakes up")
sent = {}; done()
ok(gum.rep.claimed == "KaiokenTrain" and sent[1] == "crecall" and sent[2] == "w" and kt.on,
  "after the case: claims it, walks back and trains again")

kt.command("start"); starting(); gum.rep.on = false; sent = {}; done()
ok(not kt.on and #sent == 0, "repeat turned off mid-case: doesn't walk off")
gum.rep.on = nil
kt.command("start"); starting(); kt.command("stop"); done()
ok(not kt.on and gum.rep.claimed == nil, "kt stop while paused keeps it off")
starting(); ok(not kt.gumPaused, "a case while not training changes nothing")
kt.command("start"); kt.command("gumshoe", "off")
ok(saved.gumshoe == false, "kt gumshoe off saved")
starting()
ok(kt.on, "with kt gumshoe off it keeps training")
kt.command("gumshoe", "on"); kt.command("back", "off")
ok(kt.back == nil and saved.back == "", "kt back off clears it")
gum = nil

kt.toggle()
ok(not kt.on, "kaioken train toggles it off")
kt.toggle()
ok(kt.on, "and on again")
handlers["sysUninstallPackage:kt uninstall"](nil, "KaiokenTrain")
ok(not kt.on and next(timers) == nil, "uninstalling stops it")

print("All KaiokenTrain tests passed")
