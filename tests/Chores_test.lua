-- chores: Chores. Run from the repo root: lua tests/Chores_test.lua
local id, timers, sent, out, saved, clock = 0, {}, {}, "", nil, 1000
function send(c) sent[#sent + 1] = c end
function cecho(s) out = out .. s end
function getEpoch() return clock end
function tempTimer(_, f, rep) id = id + 1; timers[id] = { f = f, rep = rep }; return id end
function killTimer(i) if i then timers[i] = nil end end
function getConnectionInfo() return "host", 1, true end
function getMudletHomeDir() return "/nonexistent-chores-test" end
local handlers = {}
function registerNamedEventHandler(_, name, event, f) handlers[event .. ":" .. name] = f end
table.save = function(_, t) saved = t end

-- the 2.x settings database, to check they're brought over
local OLD = {
  { name = "chores.fishing_path", value = '["recall;w"]' },
  { name = "chores.rest_path", value = '["e;u"]' },
  { name = "chores.quest_period", value = "[5]" },
  { name = "chores.unknown", value = '["x"]' },
}
db = { create = function() return { Constants = "C", Toggles = "T" } end,
       fetch = function(_, s) return s == "C" and OLD or {} end }
yajl = { to_value = function(s)
  local str = s:match('^%["(.*)"%]$'); if str then return { str } end
  return { tonumber(s:match("^%[(.-)%]$")) }
end }

io.exists = function(f) return f:find("Database_chores.db", 1, true) ~= nil end
MSDP = { Player = { Fatigue = 900, MaxFatigue = 1000, BasePl = 2000000000 }, Target = {} }
local P, T = MSDP.Player, MSDP.Target

local function ok(c, what) assert(c, what); print("OK  " .. what) end
local function has(cmd) for _, c in ipairs(sent) do if c == cmd then return true end end end
local function count(cmd) local n = 0; for _, c in ipairs(sent) do if c == cmd then n = n + 1 end end; return n end
local function say(l) chores.line(l) end
local function clear() sent, out = {}, "" end
local function tick(secs) clock = clock + (secs or 2); chores.tick() end

dofile("packages/Chores/src/Chores.lua")
local C = chores

ok(C.get("fishing_path") == "recall;w" and C.get("rest_path") == "e;u" and out:find("Brought over 3 settings"),
  "brings the 2.x settings over")
ok(saved and saved.fishing_path == "recall;w" and saved.quest_period == nil, "and saves them (defaults left out)")
ok(C.mode == "off" and next(timers) == nil, "off after loading")

say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(C.prompted, "sees the prompt")

-- ---- fishing
clear(); C.command("fish")
ok(C.mode == "fish" and C.activity == "fishing" and has("castout") and next(timers), "chores fish casts and runs the loop")
clear(); say("You feel a tug on your line!")
ok(has("reelin") and has("castout"), "reels and casts again on a tug")
clear(); say("You feel another tug on your line!")
ok(has("reelin") and not has("castout"), "only reels on another tug")
clear(); say("You reel in your line, but nothing was caught this time.")
ok(has("castout"), "casts again after an empty reel")
clear(); say("You feel a tug on your line!"); say("You reel in your line, but nothing was caught this time.")
ok(count("castout") == 1, "no second cast when the tug already cast")
say("You feel another tug on your line!"); clear(); say("You aren't even fishing!")
ok(has("castout"), "casts when there was no line out")
clear(); say("You pull your arm back and try to cast out your line, but it gets all tangled up.")
ok(has("castout"), "casts again on a tangle")
clear(); tick(10)
ok(not has("castout"), "no recast before recast_timeout")
clear(); tick(130)
ok(has("castout"), "recasts after recast_timeout with no bite")
clear(); say("This is not a good place to fish, find a better spot.")
ok(has("recall") and has("w") and has("castout") and C.activity == "fishing", "bad spot: walks fishing_path back")
say("You feel a tug on your line!")
ok(C.badSpots == nil, "a bite resets the bad spot count")
for _ = 1, 3 do say("This is not a good place to fish, find a better spot.") end
ok(C.mode == "off" and next(timers) == nil and out:find("check chores set fishing_path"), "stops after three bad spots")

C.command("fish")
clear(); say("You are too exhausted to fish right now.")
ok(C.activity == "resting" and has("e") and has("u") and has("land") and has("sleep") and not has("reelin"),
  "too exhausted: walks rest_path and sleeps, nothing to reel")
clear(); say("You are too exhausted to fish right now.")
ok(#sent == 0, "ignored while resting")
P.Fatigue = 1000; clear(); tick()
ok(has("wake") and has("recall") and has("castout") and C.activity == "fishing", "rested: wakes and walks back")
P.Fatigue = 100; clear(); tick()
ok(sent[1] == "reelin" and sent[#sent] == "sleep" and sent[#sent - 1] == "land" and C.activity == "resting",
  "fatigued: reels in, walks to the rest room, lands and sleeps")
clear(); tick()
ok(#sent == 0, "stays asleep while tired")
P.Fatigue = 1000; tick()

-- ---- the cook delivery
clear(); C.command("both")
ok(C.mode == "both" and C.activity == "quest" and has("reelin") and has("recall") and has("focus 'instant' roshi"),
  "chores both: delivery first (recall, instant to Roshi)")
clear(); say("Master Roshi is sitting on the toilet here, reading a magazine.")
ok(has("pursue royal cook"), "pursues the cook once Roshi is there")
clear(); say("Royal Cook says, 'Hey you, would you be able to deliver some rations to the knights?'")
ok(has("say yes"), "accepts the delivery")
clear(); say("This must go to Sir Maximillion, don't mess it up now!")
ok(has("pursue maximillion") and has("give jerky maximillion") and has("castout") and C.activity == "fishing",
  "delivers to the knight and goes back to fishing")
ok(C.nextQuest == clock + 300, "next delivery in a full period")
C.nextGrave = nil
clear(); tick(300)
ok(C.activity == "quest", "the next delivery starts when due")
say("Master Roshi is sitting on the toilet here.")
clear(); say("Royal Cook says, 'I just sent you on a delivery 4 minutes ago! Come back later.'")
ok(C.activity == "fishing" and C.nextQuest == clock + 60, "cooldown: tries again when the period is up")
tick(60); say("Master Roshi is sitting on the toilet here.")
say("Royal Cook says, 'I just sent you on a delivery! Come back in 11 seconds.'")
ok(C.nextQuest == clock + 16, "cooldown in seconds, plus 5")
tick(16)
say("Royal Cook says, 'I just sent you on a delivery! Come back in 2 minutes.'")
ok(C.nextQuest == clock + 125, "cooldown in minutes, plus 5")
tick(125)
ok(C.activity == "quest", "third delivery started")
clear(); tick(11)
ok(has("focus 'instant' roshi"), "no Roshi: instant again (2nd try)")
clear(); tick(11)
ok(has("focus 'instant' roshi"), "3rd try")
clear(); tick(11)
ok(not has("focus 'instant' roshi") and C.activity == "fishing", "gives up after 3 tries and fishes")
P.Fatigue = 100; tick(); ok(C.activity == "resting", "resting while tired")
clear(); C.nextQuest = clock; tick()
ok(has("wake") and not has("reelin") and C.activity == "quest", "a delivery wakes you up")
P.Fatigue = 1000
say("Master Roshi is sitting on the toilet here."); say("Royal Cook asks, would you be able to deliver some rations?")
clear(); say("This must go to Sir Lancelot, don't mess it up now!")
ok(has("give jerky lancelot"), "another knight")

-- ---- boss fish
clear(); say("A massive shadow emerges from the depths... Prepare for battle!")
ok(C.activity == "fishing" and out:find("boss_attack"), "boss fish without boss_attack: just warns")
C.command("set", "boss_before focus 'barrier';powerup"); C.command("set", "boss_attack kame")
C.command("set", "boss_after get all corpse")
ok(saved.boss_attack == "kame", "boss settings saved")
clear(); say("A massive shadow emerges from the depths... Prepare for battle!")
ok(has("focus 'barrier'") and has("powerup") and C.activity == "boss", "boss fish: boss_before")
clear(); tick()
ok(has("kame"), "repeats the attack")
T.name = "a giant fish"; tick()
clear(); say("A giant fish is dead!  R.I.P.")
ok(has("get all corpse") and has("castout") and C.activity == "fishing" and T.name == "", "the kill line ends it, then casts")

-- ---- rivals
clear(); say("Protei the Tuffle flies out of nowhere and attacks you!")
ok(C.activity == "fishing" and out:find("rival_attack"), "rival without rival_attack: just warns")
C.command("set", "rival_before focus 'unravel' $target"); C.command("set", "rival_attack kame")
C.command("set", "rival_after get all corpse")
clear(); say("Protei the Tuffle flies out of nowhere and attacks you!")
ok(has("focus 'unravel' protei") and has("kame protei") and C.activity == "rival", "fights the rival")
T.name = "Protei"; clear(); tick()
ok(has("kame protei"), "keeps attacking")
T.name = ""; clear(); tick()
ok(has("get all corpse") and has("castout") and C.activity == "fishing", "opponent gone from MSDP: fight over, fishing")
clear(); say("Someone is dead!  R.I.P.")
ok(#sent == 0, "a kill line outside a fight changes nothing")
C.nextQuest = clock; tick(); ok(C.activity == "quest", "delivery running")
clear(); say("Grumnir the Dwarf flies out of nowhere and attacks you!")
ok(has("kame grumnir"), "a rival in the middle of a delivery")
clear(); say("Grumnir the Dwarf is dead!  R.I.P.")
ok(has("pursue royal cook") and not has("recall") and C.activity == "quest", "back to the cook, not from the top")
clear(); say("Royal Cook exclaims, 'What are you still doing here! I asked you to deliver the jerky to Knight Glenn!'")
ok(has("give jerky glenn") and C.activity == "fishing", "the cook's reminder: delivers to that knight")

-- ---- dying
say("Vexar the Icer flies out of nowhere and attacks you!")
clear(); say("You are dead!  You are sent to the Next Dimension.")
ok(C.rival == nil and has("recall") and has("castout") and C.activity == "fishing", "died: drops the fight, back to fishing")
clear(); say("You have such a peaceful, easy feeling...")
ok(#sent == 0, "the dead room line only once every 15 s")
tick(20); C.nextQuest = clock; tick(); ok(C.activity == "quest", "delivery before dying")
say("You are sent to the Next Dimension")
ok(C.activity == "fishing" and C.nextQuest == clock + 300, "dying mid-delivery: next one a full period later")
C.command("stop"); clear(); say("You are sent to the Next Dimension")
ok(#sent == 0, "ignored when off")

-- ---- the gravedigger
C.command("both")
say("Master Roshi is sitting on the toilet here."); say("would you be able to deliver some rations")
say("This must go to Sir Bran, don't mess it up now!")
clear(); tick()
ok(C.activity == "grave" and has("focus 'instant' gine") and count("pursue gravedigger") == 1 and not has("say task"),
  "after the cook: off to Billy, no say task yet")
clear(); tick(4)
ok(has("say task"), "asks Billy from the tick")
clear(); tick(6)
ok(has("say task"), "keeps asking until he answers")
clear(); say("Gravedigger Billy says, 'Yer in luck Vorrac, plot 5 is ready to be excavated.'")
ok(has("locate shovel") and not has("dig"), "checks for a shovel first")
clear(); say("a wrought iron burial shovel"); say("a wrought iron burial shovel")
ok(has("w") and has("n") and count("dig") == 1 and has("get all") and C.activity == "fishing", "walks plot 5 and digs once")
ok(C.nextGrave == clock + 300, "next gravedigger in a full period")
clear(); C.nextGrave = clock; tick()
say("Gravedigger Billy says, 'Yer in luck Vorrac, plot 8 is ready to be excavated.'")
ok(not has("dig") and C.activity == "fishing" and out:find("No route for plot 8"), "unknown plot: skips it")
C.nextGrave = clock; tick()
say("Gravedigger Billy says, 'Sorry chum, no burial plots need excavating. Check back in 4 minutes.'")
ok(C.activity == "fishing" and C.nextGrave == clock + 245, "no plots ready: minutes plus 5")
C.nextGrave = clock; tick()
say("Gravedigger Billy says, 'Sorry chum, no burial plots need excavating. Check back in 30 seconds.'")
ok(C.nextGrave == clock + 35, "seconds plus 5")
C.nextGrave = clock; tick()
say("Gravedigger Billy says, 'Yer in luck Vorrac, plot 1 is ready to be excavated.'")
clear(); tick()
ok(#sent == 0, "waits for the locate reply")
say("No matching items found in your inventory.")
ok(has("buy 1") and has("s") and has("dig"), "no shovel: buys one, then digs")
clear(); say("a wrought iron burial shovel"); say("No matching items found in your inventory.")
ok(#sent == 0, "locate replies ignored outside the shovel step")
C.nextGrave = clock; tick()
say("Gravedigger Billy says, 'Yer in luck Vorrac, plot 2 is ready to be excavated.'")
clear(); tick(12)
ok(has("buy 1") and has("dig"), "no locate reply at all: buys and digs")
C.nextGrave = clock; tick()
say("Gravedigger Billy exclaims, 'I already done told you! I need you to go dig up burial plot 5!'")
ok(C.grave.plot == 5, "Billy's reminder counts as the assignment")
clear(); say("Gravedigger Billy exclaims, 'I already done told you! I need you to go dig up burial plot 5!'")
ok(#sent == 0, "a repeated reminder is ignored")
say("a wrought iron burial shovel")
C.nextGrave = clock; tick()
for _ = 1, 20 do tick() end
ok(C.activity == "grave", "still on it after 40 s of pursuing")
say("Gravedigger Billy says, 'Yer in luck Vorrac, plot 4 is ready to be excavated.'")
ok(has("locate shovel"), "a late answer still counts")
say("a wrought iron burial shovel")
C.nextGrave = clock; tick(); tick(95)
ok(C.activity == "fishing", "no answer in 90 s: back to fishing")
C.nextGrave = clock; tick(); say("You are sent to the Next Dimension")
ok(C.activity == "fishing" and C.nextGrave == clock + 300, "dying at Billy's: next one a full period later")

P.BasePl = nil; C.warnedLowPl = nil; C.nextGrave = clock; clear(); tick()
ok(not has("pursue gravedigger") and out:find("type score"), "base PL unknown: skips it and says to type score")
P.BasePl = 500; C.warnedLowPl = nil; C.nextGrave = clock; clear(); tick()
ok(not has("pursue gravedigger") and C.activity == "fishing" and C.nextGrave == clock + 300 and out:find("under"),
  "base PL too low: skips it, looks again next period")
C.nextGrave = clock; clear(); tick()
ok(not out:find("under"), "says so only once")
P.BasePl = 2000000000; P.Pl = 10; C.nextGrave = clock; clear(); tick()
ok(has("pursue gravedigger"), "only the base PL counts")
C.command("stop")

C.command("set", "grave_path off")
ok(C.get("grave_path") == "" and saved.grave_path == "", "grave_path off empties it")
C.command("both"); say("Master Roshi is sitting on the toilet here."); say("would you be able to deliver some rations")
say("This must go to Sir Bran, don't mess it up now!")
clear(); tick()
ok(not has("pursue gravedigger") and C.nextGrave == nil and out:find("grave_path"), "no grave_path: no excavation")
C.command("set", "grave_path default")
ok(C.get("grave_path") == "focus 'instant' gine;pursue gravedigger" and saved.grave_path == nil, "default puts it back")
C.command("set", "grave_path board ship;n"); C.nextGrave = clock; clear(); tick()
ok(sent[1] == "reelin" and has("board ship") and has("pursue gravedigger"), "a path without pursue gets one added")
C.command("stop")

-- ---- quest only, stopping, no fishing path
C.command("quest")
ok(C.activity == "quest" and not has("castout"), "chores quest: delivery, no fishing")
say("Master Roshi is sitting on the toilet here."); say("would you be able to deliver some rations")
clear(); say("This must go to Sir Kay, don't mess it up now!")
ok(not has("castout") and has("recall") and C.activity == "idle", "quest only: walks back, then idles")
clear(); C.command("stop")
ok(C.mode == "off" and next(timers) == nil and not has("reelin"), "stop from idle: nothing to reel")
C.command("fish"); clear(); C.command("off")
ok(has("reelin") and C.mode == "off", "chores off while fishing reels in")
clear(); say("You feel a tug on your line!")
ok(has("reelin") and not has("castout"), "off: a tug is still reeled, no cast")
C.command("set", "fishing_path off")
C.command("both"); say("Master Roshi is sitting on the toilet here.")
clear(); say("Royal Cook says, 'I just sent you on a delivery 3 minutes ago! Come back later.'")
ok(has("castout") and C.activity == "fishing" and out:find("fishing_path"), "no fishing_path: warns, casts where it is")
C.command("stop")

-- ---- the cook path
C.command("set", "cook_path n;e"); clear(); C.command("start")
ok(C.mode == "both" and has("n") and has("e") and not has("focus 'instant' roshi") and C.quest.step == "roshi",
  "chores start = both; a travel-only cook path still checks for Roshi")
say("Master Roshi is sitting on the toilet here.")
ok(C.quest.step == "cook", "Roshi moves it on to the cook")
C.command("stop")
C.command("set", "cook_path recall;pursue royal cook"); clear(); C.command("start", "quest")
ok(has("pursue royal cook") and C.quest.step == "cook", "a cook path that pursues skips Roshi")
clear(); say("would you be able to deliver some rations")
ok(has("say yes"), "and accepts straight away")
C.command("stop")

-- ---- settings, status, help
C.command("set", "quest_period 10")
ok(C.get("quest_period") == 10 and saved.quest_period == 10, "a number setting")
out = ""; C.command("set", "quest_period soon")
ok(out:find("is a number") and C.get("quest_period") == 10, "refuses a non-number")
out = ""; C.command("set", "nope 3")
ok(out:find("No setting called nope"), "unknown setting")
out = ""; C.command("set", "chores.rest_path")
ok(out:find("rest_path = e;u"), "shows one (the old chores. prefix works)")
out = ""; C.command("set")
ok(out:find("grave_plot_7") and out:find("w;n;n;n;w;w;w;n"), "lists every setting")
C.command("debug", "on"); ok(C.debug and saved.debug == true, "debug saved")
C.command("debug", "off")
out = ""; C.command("status")
ok(out:find("Off") and out:find("fishing_path isn't set"), "status when off")
C.command("both"); out = ""; C.command("status")
ok(out:find("Mode") and out:find("Next cook delivery"), "status when on")
out = ""; say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(out:find("chores:both<white>/<green>quest", 1, true), "shows the bot state on the prompt")
out = ""; C.command()
ok(out:find("chores start") and out:find("chores set <name> <value>"), "help")
handlers["sysUninstallPackage:chores uninstall"](nil, "Chores")
ok(C.mode == "off" and next(timers) == nil, "uninstalling stops it")
handlers["sysDisconnectionEvent:chores disconnect"]()
C.command("fish"); clear(); tick(200)
ok(#sent == 0, "does nothing before a prompt after reconnecting")
C.command("stop")

-- ---- Gumshoe's gum repeat
say("[Pl: 4,320 | Ki: 100%] [HT]")
C.command("set", "fishing_path recall;w")
local held, released = {}, {}
gum = { rep = {}, hold = function(w) held[#held + 1] = w end, release = function(w) released[#released + 1] = w end }
local function starting() handlers["gumshoe.repeat.starting:chores gumshoe starting"]() end
local function done() gum.rep.claimed = nil; handlers["gumshoe.repeat.done:chores gumshoe done"]() end
C.command("fish"); clear(); starting()
ok(C.mode == "off" and next(timers) == nil and has("reelin") and C.gumPaused, "a case pauses fishing (reels in)")
clear(); done()
ok(gum.rep.claimed == "Chores" and C.mode == "fish" and has("recall") and has("w") and has("castout") and next(timers),
  "after the case: claims it, walks fishing_path and fishes")
P.Fatigue = 100; tick(); ok(C.activity == "resting", "resting")
clear(); starting()
ok(has("wake") and C.mode == "off", "asleep when the case starts: wakes up")
P.Fatigue = 1000; done()
C.command("stop")

C.command("both"); clock = clock + 1
ok(C.activity == "quest", "a delivery under way")
starting()
ok(C.gumPaused and C.gumPaused.nextQuest == clock, "an interrupted delivery is done again after the case")
clear(); done()
ok(C.mode == "both" and has("castout"), "back to fishing in both")
clear(); tick()
ok(C.activity == "quest" and has("recall"), "and the delivery runs again")
C.command("stop")

C.command("fish"); say("Protei the Tuffle flies out of nowhere and attacks you!")
clear(); starting()
ok(held[1] == "Chores" and C.mode == "fish" and C.activity == "rival", "in a fight: Gumshoe waits for it")
clear(); say("Protei the Tuffle is dead!  R.I.P.")
ok(released[1] == "Chores" and C.mode == "off" and C.gumPaused and has("get all corpse") and not has("castout"),
  "the fight ends: rival_after, then paused and Gumshoe let go")
done()
C.command("quest"); starting(); clear(); done()
ok(C.mode == "quest" and not has("recall") and C.activity == "idle", "quest mode: no walk, waits for the next delivery")
clear(); tick()
ok(C.activity == "quest", "which runs straight away (it was under way)")
C.command("stop")

C.command("fish"); starting(); C.command("stop"); done()
ok(C.mode == "off" and gum.rep.claimed == nil, "chores stop while paused keeps it off")
C.command("fish"); starting(); gum.rep.on = false; clear(); done()
ok(C.mode == "off" and #sent == 0, "repeat turned off mid-case: doesn't walk off")
gum.rep.on = nil
C.command("set", "fishing_path off"); C.command("fish"); out = ""; starting()
ok(out:find("No fishing_path set"), "warns that it can't come back without fishing_path")
done(); ok(C.mode == "off", "and stays off")
C.command("set", "fishing_path recall;w")
C.command("gumshoe", "off"); ok(saved.gumshoe == false, "chores gumshoe off saved")
C.command("fish"); starting(); ok(C.mode == "fish", "with gumshoe off it keeps going")
C.command("stop"); C.command("gumshoe", "on")
starting(); ok(not C.gumPaused, "a case while chores is off changes nothing")
gum = nil

-- a settings file wins over the old database
local loaded = { fishing_path = "x" }
table.load = function(_, t) for k, v in pairs(loaded) do t[k] = v end end
local realOpen = io.open
io.open = function(f, ...) if f:find("nonexistent%-chores%-test") then return {} end return realOpen(f, ...) end
chores = nil; out = ""
dofile("packages/Chores/src/Chores.lua")
io.open = realOpen
io.exists = nil
ok(chores.get("fishing_path") == "x" and chores.get("rest_path") == "" and not out:find("Brought over"),
  "with a settings file the old database isn't read")

print("All Chores tests passed")
