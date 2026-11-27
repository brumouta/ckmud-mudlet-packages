-- chores: fishing, the royal cook delivery and the gravedigger excavation.
-- Modes: fish | quest | both. In quest/both the deliveries (cook first, then Billy) preempt fishing
-- and resting when their cooldown is up, and fishing resumes afterwards.
-- Stats (fatigue, base PL, opponent) come from the MSDP package.
chores = chores or {}
local C = chores

local function info(color, msg) cecho("\n<" .. color .. ">[chores] <white>" .. msg .. "\n") end
local function now() return getEpoch() end

-- ---------------------------------------------------------------- settings (saved)
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/chores.lua"
local GRAVE_MIN_PL = 1000000000   -- Billy's power level requirement

C.SETTINGS = {
  -- name, default, what it is (numbers are kept as numbers)
  { "fishing_path",   "",                                        "Commands to reach your fishing spot, from the rest room and after a delivery (start it with a recall)" },
  { "rest_path",      "",                                        "Commands from the fishing spot to your rest room" },
  { "rest_below",     20,                                        "Rest when fatigue drops below this %" },
  { "recast_timeout", 120,                                       "Seconds without a bite before casting again" },
  { "cook_path",      "recall;focus 'instant' roshi",            "Commands to reach the royal cook (may end with pursue royal cook)" },
  { "quest_period",   5,                                         "Minutes between cook deliveries" },
  { "grave_path",     "focus 'instant' gine;pursue gravedigger", "Commands to reach Gravedigger Billy (empty: no excavation)" },
  { "grave_period",   5,                                         "Minutes between gravedigger tasks" },
  { "grave_plot_1",   "w;w;w;w;w;s",                             "From Billy to plot 1" },
  { "grave_plot_2",   "w;w;w;s",                                 "From Billy to plot 2" },
  { "grave_plot_3",   "w;w;w;w;w;n;w;n",                         "From Billy to plot 3" },
  { "grave_plot_4",   "w;w;w;w;n;n",                             "From Billy to plot 4" },
  { "grave_plot_5",   "w;w;n;n",                                 "From Billy to plot 5" },
  { "grave_plot_6",   "w;n;n;n;w;w;w;w;w;n",                     "From Billy to plot 6" },
  { "grave_plot_7",   "w;n;n;n;w;w;w;n",                         "From Billy to plot 7" },
  { "boss_before",    "",                                        "Commands before fighting a boss fish" },
  { "boss_attack",    "",                                        "Attack repeated on a boss fish (empty: you fight it)" },
  { "boss_after",     "",                                        "Commands after the boss fish dies" },
  { "rival_before",   "",                                        "Commands before fighting a rival ($target is the rival)" },
  { "rival_attack",   "",                                        "Attack repeated on a rival, the target is added (empty: you fight it)" },
  { "rival_after",    "",                                        "Commands after a rival fight ($target is the rival)" },
}
local DEFAULT, NUMERIC = {}, {}
for _, s in ipairs(C.SETTINGS) do DEFAULT[s[1]] = s[2]; NUMERIC[s[1]] = type(s[2]) == "number" end

C.set = C.set or {}
C.debug = C.debug or false
local function get(name)
  local v = C.set[name]
  if v == nil then return DEFAULT[name] end
  return v
end
C.get = get

function C.save()
  if type(table.save) ~= "function" then return end
  local t = { debug = C.debug }
  for name in pairs(DEFAULT) do if C.set[name] ~= nil then t[name] = C.set[name] end end
  pcall(table.save, FILE, t)
end

local function take(t)
  for name in pairs(DEFAULT) do
    local v = t[name]
    if NUMERIC[name] then v = tonumber(v) end
    if v ~= nil and v ~= DEFAULT[name] then C.set[name] = v end
  end
  if type(t.debug) == "boolean" then C.debug = t.debug end
end

-- Settings from Chores 2.x lived in Mudlet's "Chores" database (CH constant chores.<name>=...):
-- bring them over once, the first time 3.x loads without a settings file.
local function migrate()
  if type(db) ~= "table" or type(db.create) ~= "function" or type(yajl) ~= "table" then return end
  -- only if 2.x left a database (Mudlet keeps it as Database_chores.db): don't create an empty one
  local dbFile = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/Database_chores.db"
  local exists = type(io.exists) == "function" and io.exists(dbFile)
  if not exists then local f = io.open(dbFile); if f then f:close(); exists = true end end
  if not exists then return end
  local ok, schema = pcall(db.create, db, "Chores", {
    Toggles = { name = "", value = 0, _unique = { "name" }, _violations = "REPLACE" },
    Constants = { name = "", value = "", _unique = { "name" }, _violations = "REPLACE" },
  })
  if not ok or not schema then return end
  local t, n = {}, 0
  local okC, rows = pcall(db.fetch, db, schema.Constants)
  for _, r in ipairs(okC and rows or {}) do
    local name = type(r.name) == "string" and r.name:match("^chores%.(.+)$")
    local okV, v = pcall(yajl.to_value, r.value or "")
    if name and DEFAULT[name] ~= nil and okV and type(v) == "table" then t[name] = v[1]; n = n + 1 end
  end
  local okT, toggles = pcall(db.fetch, db, schema.Toggles)
  for _, r in ipairs(okT and toggles or {}) do
    if r.name == "chores.debug" then t.debug = r.value == 1 end
  end
  take(t)
  C.save()
  if n > 0 then info("green", "Brought over " .. n .. " settings from Chores 2.x (chores set lists them).") end
end

local function load()
  local t = {}
  if type(table.load) == "function" and io.open(FILE) then
    pcall(table.load, FILE, t)
    take(t)
  else
    migrate()
  end
end
load()

-- ---------------------------------------------------------------- state
-- (a reinstall starts from off: the old copy's loop is stopped)
if C.timer and type(killTimer) == "function" then killTimer(C.timer) end
C.timer = nil
C.mode = "off"          -- off | fish | quest | both
C.activity = "idle"     -- idle | fishing | resting | quest | grave | boss | rival
C.quest = {}
C.prompted = false

local function trace(msg) if C.debug then cecho("\n<yellow>[chores debug] " .. msg .. "\n") end end

local function player() local M = rawget(_G, "MSDP"); return M and M.Player or {} end
local function target() local M = rawget(_G, "MSDP"); return M and M.Target or {} end

local function connected()
  if type(getConnectionInfo) == "function" then
    local _, _, isConnected = getConnectionInfo()
    if isConnected == false then return false end
  end
  return C.prompted
end

local function sendAll(cmds)
  for cmd in tostring(cmds or ""):gmatch("[^;]+") do send(cmd) end
end
local function sendPath(name) local p = get(name); if p ~= "" then sendAll(p) end end

local function wantsFishing() return C.mode == "fish" or C.mode == "both" end
local function wantsQuest() return C.mode == "quest" or C.mode == "both" end

local function seconds(n, unit) return n * (unit:sub(1, 6) == "minute" and 60 or 1) + 5 end

function C.castout()
  C.lastCast = now()
  C.lineOut = true
  send("castout")
end

-- Walk back to the fishing spot (from the end of a delivery or the rest room) and cast again;
-- quest-only mode walks back too, then idles there.
function C.returnToFishing()
  local path = get("fishing_path")
  if path ~= "" then
    sendAll(path)
  elseif not C.warnedNoPath then
    C.warnedNoPath = true
    info("yellow", "Set chores set fishing_path <commands> so I can walk back to the fishing spot.")
  end
  if wantsFishing() then
    C.activity = "fishing"
    C.castout()
  else
    C.activity = "idle"
  end
end

-- ---------------------------------------------------------------- fishing
function C.tug()
  -- reelin always lands the fish; cast again right away while fishing
  send("reelin")
  C.lineOut = false
  if C.activity == "fishing" then
    C.badSpots = nil   -- a bite proves the spot is fine
    C.castout()
  end
end

-- "This is not a good place to fish": we drifted off the spot. Walk back and try again; three
-- times without a bite in between means the path itself is wrong, so stop.
function C.badSpot()
  if C.activity ~= "fishing" then return end
  C.badSpots = (C.badSpots or 0) + 1
  if C.badSpots >= 3 then
    info("red", "Still not a good fishing spot after walking back: check chores set fishing_path. Stopping.")
    C.activity = "idle"   -- no line out, nothing to reel
    C.stop()
    return
  end
  info("white", "Bad fishing spot, walking back")
  C.returnToFishing()
end

function C.anotherTug()
  -- multi-catch: the line is still out with the next fish, only reel
  send("reelin")
  C.lineOut = false
  if C.activity == "fishing" then C.lastCast = now() end
end

-- "You aren't even fishing!" / "...nothing was caught this time.": no line in the water. Cast
-- again, unless tug() has already put a fresh one out.
function C.lineEmpty()
  if C.activity ~= "fishing" or C.lineOut then return end
  C.castout()
end

function C.tangle()
  if C.activity == "fishing" then C.castout() end
end

-- Go to the rest room and sleep. noReel: the cast never landed, so there's no line to pull in.
function C.goRest(noReel)
  C.activity = "resting"
  if not noReel then send("reelin") end
  sendPath("rest_path")
  send("land")   -- can't sleep while flying
  send("sleep")
end

function C.tooExhausted()
  if C.activity ~= "fishing" then return end
  info("white", "Too exhausted to fish, going to rest")
  C.goRest(true)
end

-- ---------------------------------------------------------------- the royal cook delivery
function C.startQuest()
  if C.activity == "resting" then send("wake")          -- the delivery outranks a nap
  elseif C.activity == "fishing" then send("reelin") end
  C.activity = "quest"
  local path = get("cook_path")
  if path:find("pursue", 1, true) then
    C.quest = { step = "cook", tries = 1, deadline = now() + 20 }   -- the path goes all the way
  else
    C.quest = { step = "roshi", tries = 1, deadline = now() + 10 }
  end
  trace("quest: travelling to the cook")
  sendAll(path)
end

function C.roshiSeen()
  local q = C.quest
  if C.activity ~= "quest" or q.step ~= "roshi" then return end
  q.step, q.deadline = "cook", now() + 15
  send("pursue royal cook")
end

function C.cookAsked()
  local q = C.quest
  if C.activity ~= "quest" or q.step ~= "cook" then return end
  q.step, q.deadline = "name", now() + 15
  send("say yes")
end

function C.deliverTo(knight)
  send("pursue " .. knight)
  send("give jerky " .. knight)
  C.questDone("rations delivered to " .. knight, get("quest_period") * 60)
end

function C.knightNamed(name)
  local q = C.quest
  if C.activity ~= "quest" or q.step ~= "name" then return end
  C.deliverTo(name:lower())
end

-- "I asked you to deliver the jerky to Knight Glenn!": already accepted (before a rival
-- interrupted, say), so take the jerky straight to the knight
function C.knightReminded(name)
  if C.activity ~= "quest" then return end
  C.deliverTo(name:lower())
end

-- "I just sent you on a delivery 3 minutes ago": try again when the period is actually up
function C.questCooldown(minutes)
  if C.activity ~= "quest" then return end
  local wait = math.max(get("quest_period") * 60 - minutes * 60, 30)
  C.questDone("the cook is on cooldown, trying again in " .. wait .. "s", wait)
end

-- "Come back in 11 seconds."
function C.questCooldownLeft(n, unit)
  if C.activity ~= "quest" then return end
  local wait = seconds(n, unit)
  C.questDone("the cook is on cooldown, trying again in " .. wait .. "s", wait)
end

function C.questDone(why, wait)
  info("white", "Quest: " .. why)
  C.nextQuest = now() + wait
  C.returnToFishing()
end

function C.questFail(reason)
  info("yellow", "Quest aborted: " .. reason)
  C.nextQuest = now() + get("quest_period") * 60
  C.returnToFishing()
end

-- ---------------------------------------------------------------- the gravedigger
function C.startGrave()
  -- Billy won't deal with us under 1 billion base PL (base, so damage and forms don't sway it)
  local pl = player().BasePl
  if not pl or pl < GRAVE_MIN_PL then
    if not C.warnedLowPl then
      C.warnedLowPl = true
      if pl then
        info("white", "Skipping the gravedigger: base power level " .. pl .. " is under " .. GRAVE_MIN_PL .. ".")
      else
        info("white", "Base power level unknown: type score once so I can read it (the gravedigger needs 1 billion).")
      end
    end
    C.nextGrave = now() + get("grave_period") * 60   -- look again next period, not every tick
    return
  end
  local path = get("grave_path")
  if path == "" then
    if not C.warnedNoGrave then
      C.warnedNoGrave = true
      info("white", "No gravedigger excavation: chores set grave_path <commands> turns it on.")
    end
    C.nextGrave = nil   -- off until set and started again
    return
  end
  if C.activity == "resting" then send("wake")
  elseif C.activity == "fishing" then send("reelin") end
  C.activity = "grave"
  -- pursue takes a while, so `say task` goes out from the tick, again every few seconds until
  -- Billy answers (or the travel time runs out)
  C.grave = { step = "travel", deadline = now() + 90, nextSay = now() + 3 }
  trace("grave: travelling to Billy")
  sendAll(path)
  if not path:find("pursue", 1, true) then send("pursue gravedigger") end
end

function C.gravePlot(plot)
  if C.activity ~= "grave" then return end
  local path = (plot >= 1 and plot <= 7) and get("grave_plot_" .. plot) or ""
  if path == "" then
    info("yellow", "No route for plot " .. plot .. " (chores set grave_plot_" .. plot .. "), skipping it.")
    return C.graveFail("plot " .. plot .. " has no route")
  end
  -- make sure we carry a shovel before walking out; the reply decides whether to buy one first
  trace("grave: plot " .. plot .. ", checking for a shovel")
  C.grave.plot, C.grave.step, C.grave.deadline = plot, "shovel", now() + 10
  send("locate shovel")
end

-- "I need you to go dig up burial plot 5!": already assigned. Take it as the assignment unless
-- we're already working on that plot.
function C.graveReminded(plot)
  if C.activity ~= "grave" then return end
  local g = C.grave
  if g.plot == plot and g.step ~= "travel" then return end
  trace("grave: Billy reminded us of plot " .. plot)
  C.gravePlot(plot)
end

function C.shovelFound()
  local g = C.grave
  if C.activity ~= "grave" or not g or g.step ~= "shovel" then return end
  C.graveDig()
end

function C.shovelMissing()
  local g = C.grave
  if C.activity ~= "grave" or not g or g.step ~= "shovel" then return end
  info("white", "No burial shovel, buying one from Billy")
  send("buy 1")
  C.graveDig()
end

function C.graveDig()
  local plot = C.grave.plot
  C.grave.step = "digging"
  trace("grave: walking to plot " .. plot .. " and digging")
  sendAll(get("grave_plot_" .. plot))
  send("dig")
  send("get all")   -- pick up whatever the plot turned up
  C.graveDone("excavated plot " .. plot, get("grave_period") * 60)
end

-- "Sorry chum, no burial plots need excavating. Check back in 4 minutes."
function C.graveCooldown(n, unit)
  if C.activity ~= "grave" then return end
  local wait = seconds(n, unit)
  C.graveDone("no plots ready, checking back in " .. wait .. "s", wait)
end

function C.graveDone(why, wait)
  info("white", "Gravedigger: " .. why)
  C.nextGrave = now() + wait
  C.returnToFishing()
end

function C.graveFail(reason)
  info("yellow", "Gravedigger aborted: " .. reason)
  C.nextGrave = now() + get("grave_period") * 60
  C.returnToFishing()
end

-- ---------------------------------------------------------------- fights
-- Boss fish: fight until the kill line (or the MSDP opponent clears), then cast again.
function C.bossAppeared()
  if C.mode == "off" or C.activity == "boss" then return end
  if get("boss_attack") == "" then
    return info("red", "A boss fish attacked! chores set boss_attack <attack> fights back by itself.")
  end
  C.boss = { engaged = false, deadline = now() + 20 }
  C.activity = "boss"
  sendPath("boss_before")
end

function C.bossDead()
  if C.activity ~= "boss" then return end
  C.boss = nil
  sendPath("boss_after")
  -- it hooked at the fishing spot: nowhere to walk
  if wantsFishing() then
    C.activity = "fishing"
    C.castout()
  else
    C.activity = "idle"
  end
end

-- "<Name> flies out of nowhere and attacks you!" while out and about: fight back, then carry on.
function C.rivalAttacked(name)
  if C.mode == "off" or C.activity == "rival" then return end
  local attack = get("rival_attack")
  if attack == "" then
    return info("red", "A rival attacked! chores set rival_attack <attack> fights back by itself.")
  end
  local who = name:lower()
  C.rival = { target = who, resume = C.activity, engaged = false, deadline = now() + 20 }
  C.activity = "rival"
  local before = get("rival_before")
  if before ~= "" then sendAll((before:gsub("%$target", who))) end
  send(attack .. " " .. who)
end

function C.rivalOver()
  local r = C.rival or {}
  C.rival = nil
  local after = get("rival_after")
  if after ~= "" then sendAll((after:gsub("%$target", r.target or ""))) end
  if r.resume == "quest" then
    -- still on Earth: straight back to the cook, who asks again or reminds us of the knight
    C.activity = "quest"
    C.quest = { step = "cook", deadline = now() + 15 }
    send("pursue royal cook")
  elseif r.resume == "grave" then
    C.activity = "idle"
    C.startGrave()   -- from the top: its path works from anywhere
  else
    -- the fishing path also covers an interrupted rest: the fatigue check sends us back to bed
    C.returnToFishing()
  end
end

-- "<Name> is dead!  R.I.P.": the end of the fight. MSDP's opponent doesn't always clear after a
-- kill, so this settles it (the MSDP check stays for fights that end without one).
function C.somethingDied()
  local T = target()
  T.name = ""
  if C.activity == "boss" then C.bossDead()
  elseif C.activity == "rival" then C.rivalOver() end
end

-- "You are sent to the Next Dimension" / the dead room: drop any fight or delivery and head back
-- to fishing. The dead-room line repeats for every command, so only once every 15 s.
function C.died()
  if C.mode == "off" then return end
  local t = now()
  if C.lastDeath and t - C.lastDeath < 15 then return end
  C.lastDeath = t
  info("red", "We died! Heading back to the fishing spot.")
  C.rival, C.boss = nil, nil
  if C.activity == "quest" then C.nextQuest = t + get("quest_period") * 60
  elseif C.activity == "grave" then C.nextGrave = t + get("grave_period") * 60 end
  C.returnToFishing()
end

-- ---------------------------------------------------------------- the tick (every 2 s)
local function fightTick(f, done, attack)
  local name = target().name
  local fighting = name ~= nil and name ~= ""
  if fighting then f.engaged = true end
  if f.engaged and not fighting then done()                   -- opponent gone from MSDP
  elseif not f.engaged and now() > f.deadline then done()     -- never saw it start
  else send(attack) end
end

function C.tick()
  if C.mode == "off" or not connected() then return end
  local t, act = now(), C.activity

  -- deliveries preempt fishing and resting (the cook before Billy)
  if wantsQuest() and (act == "fishing" or act == "idle" or act == "resting") then
    if C.nextQuest and t >= C.nextQuest then return C.startQuest()
    elseif C.nextGrave and t >= C.nextGrave then return C.startGrave() end
  end

  if act == "grave" then
    local g = C.grave
    if g.step == "travel" and t >= (g.nextSay or 0) then
      send("say task")   -- keep asking: the pursue may still be walking
      g.nextSay = t + 5
    end
    if t > g.deadline then
      if g.step == "shovel" then C.shovelMissing()   -- no locate reply at all: buy one
      else C.graveFail("timed out at step '" .. g.step .. "'") end
    end
  elseif act == "quest" then
    local q = C.quest
    if t > q.deadline then
      if q.step == "roshi" and (q.tries or 1) < 3 then
        q.tries, q.deadline = (q.tries or 1) + 1, t + 10
        sendAll(get("cook_path"))
      else
        C.questFail("timed out waiting at step '" .. q.step .. "'")
      end
    end
  elseif act == "fishing" then
    local P = player()
    local pct = (P.Fatigue and P.MaxFatigue and P.MaxFatigue > 0) and (P.Fatigue / P.MaxFatigue * 100) or nil
    if pct and pct < get("rest_below") then C.goRest()
    elseif t - (C.lastCast or 0) > get("recast_timeout") then C.castout() end   -- no bite for a while
  elseif act == "resting" then
    local P = player()
    if P.Fatigue and P.MaxFatigue and P.Fatigue >= P.MaxFatigue then
      send("wake")
      C.returnToFishing()
    end
  elseif act == "boss" then
    fightTick(C.boss, C.bossDead, get("boss_attack"))
  elseif act == "rival" then
    fightTick(C.rival, C.rivalOver, get("rival_attack") .. " " .. C.rival.target)
  end
end

-- ---------------------------------------------------------------- start / stop
function C.stop(quiet)
  if C.timer then killTimer(C.timer) end
  C.timer = nil
  if C.activity == "fishing" then send("reelin") end
  local was = C.mode
  C.mode, C.activity = "off", "idle"
  if was ~= "off" and not quiet then info("white", "Stopped.") end
end

function C.start(mode)
  mode = mode or "both"
  if C.mode ~= "off" then C.stop(true) end
  if not rawget(_G, "MSDP") then info("red", "Chores needs the MSDP package for your stats (fatigue, base PL).") end
  C.mode = mode
  C.warnedNoPath, C.warnedNoGrave, C.warnedLowPl, C.badSpots = nil, nil, nil, nil
  C.quest, C.nextQuest = {}, nil
  -- the gravedigger goes on the first tick after the cook delivery
  C.nextGrave = wantsQuest() and now() or nil
  info("green", "Mode: " .. mode .. " (chores stop to stop)")
  C.timer = tempTimer(2, C.tick, true)
  if wantsQuest() then
    C.startQuest()   -- delivery first; finishing it drops into the main loop
  elseif wantsFishing() then
    C.activity = "fishing"
    C.castout()
  else
    C.activity = "idle"
  end
end

-- ---------------------------------------------------------------- game lines (every-line trigger)
local EXACT = {
  ["You feel a tug on your line!"] = function() C.tug() end,
  ["You feel another tug on your line!"] = function() C.anotherTug() end,
  ["This is not a good place to fish, find a better spot."] = function() C.badSpot() end,
  ["You are too exhausted to fish right now."] = function() C.tooExhausted() end,
  ["You aren't even fishing!"] = function() C.lineEmpty() end,
  ["You reel in your line, but nothing was caught this time."] = function() C.lineEmpty() end,
  ["You pull your arm back and try to cast out your line, but it gets all tangled up."] = function() C.tangle() end,
  ["A massive shadow emerges from the depths... Prepare for battle!"] = function() C.bossAppeared() end,
}
local CONTAINS = {
  { "Your line gets tangled", function() C.tangle() end },
  { "Master Roshi is sitting on the toilet here", function() C.roshiSeen() end },
  { "would you be able to deliver some rations", function() C.cookAsked() end },
  { "a wrought iron burial shovel", function() C.shovelFound() end },
  { "No matching items found in your inventory", function() C.shovelMissing() end },
  { "You are sent to the Next Dimension", function() C.died() end },
  { "such a peaceful, easy feeling", function() C.died() end },
}
local PATTERNS = {
  { "This must go to Sir (%w+)", function(n) C.knightNamed(n) end },
  { "I asked you to deliver the jerky to %w+ (%w+)!", function(n) C.knightReminded(n) end },
  { "Yer in luck .+, plot (%d+) is ready to be excavated", function(p) C.gravePlot(tonumber(p)) end },
  { "I need you to go dig up burial plot (%d+)!", function(p) C.graveReminded(tonumber(p)) end },
  { "no burial plots need excavating%. Check back in (%d+) (%a+)%.", function(n, u) C.graveCooldown(tonumber(n), u) end },
  { "I just sent you on a delivery (%d+) minutes? ago", function(n) C.questCooldown(tonumber(n)) end },
  { "I just sent you on a delivery! Come back in (%d+) (%a+)%.", function(n, u) C.questCooldownLeft(tonumber(n), u) end },
  { "is dead!%s+R%.I%.P%.", function() C.somethingDied() end },
  { "^([%w_]+).- flies out of nowhere and attacks you!$", function(n) C.rivalAttacked(n) end },
}

function C.line(l)
  if type(l) ~= "string" then return end
  if l:find("^%[Pl: [%d,]+ |") then
    C.prompted = true
    if C.mode ~= "off" then cecho("<white>[<green>chores:" .. C.mode .. "<white>/<green>" .. C.activity .. "<white>]") end
    return
  end
  local f = EXACT[l]
  if f then return f() end
  for _, c in ipairs(CONTAINS) do
    if l:find(c[1], 1, true) then return c[2]() end
  end
  for _, p in ipairs(PATTERNS) do
    local a, b = l:match(p[1])
    if a then return p[2](a, b) end
  end
end

function C.disconnected() C.prompted = false end

-- ---------------------------------------------------------------- `chores` command
C.HELP = {
  { "chores start [fish|quest|both]", "Start (both if not given): quest = cook and gravedigger deliveries, both = fish in between" },
  { "chores fish|quest|both",         "The same as chores start fish|quest|both" },
  { "chores stop",                    "Stop (chores off too)" },
  { "chores status",                  "What it's doing and when the next deliveries are" },
  { "chores set",                     "Every setting and its value" },
  { "chores set <name> <value>",      "Change one (saved); <value> default puts it back, off empties it" },
  { "chores debug on|off",            "Trace every step, for when a cycle stalls" },
  { "chores update",                  "Update Chores to the latest release" },
}

function C.help()
  cecho("\n<cyan>Chores (chores):\n")
  for _, h in ipairs(C.HELP) do cecho(string.format("  <yellow>%-32s<white>%s\n", h[1], h[2])) end
  cecho("  <grey>Start fishing at your fishing spot, holding a pole. Set fishing_path and rest_path first.\n")
end

local function inWhen(at)
  if not at then return "off" end
  local s = math.max(0, math.floor(at - now()))
  return s == 0 and "now" or ("in " .. string.format("%d:%02d", math.floor(s / 60), s % 60))
end

function C.status()
  if C.mode == "off" then
    info("white", "Off. chores start [fish|quest|both] to start.")
  else
    info("white", "Mode <green>" .. C.mode .. "<white>, now <green>" .. C.activity .. "<white>.")
    if wantsQuest() then
      info("white", "Next cook delivery " .. inWhen(C.nextQuest) .. ", next gravedigger " .. inWhen(C.nextGrave) .. ".")
    end
  end
  for _, name in ipairs({ "fishing_path", "rest_path" }) do
    if get(name) == "" then info("yellow", name .. " isn't set: chores set " .. name .. " <commands>") end
  end
  if not rawget(_G, "MSDP") then info("red", "The MSDP package isn't installed: Chores needs it for your stats.") end
end

function C.listSettings()
  cecho("\n<cyan>Chores settings (chores set <name> <value>):\n")
  for _, s in ipairs(C.SETTINGS) do
    local v, changed = get(s[1]), C.set[s[1]] ~= nil
    local shown = v == "" and "<grey>(empty)" or tostring(v)
    cecho(string.format("  <yellow>%-15s %s%s  <grey>%s\n", s[1], changed and "<green>" or "<white>", shown, s[3]))
  end
end

function C.setting(name, value)
  if not name then return C.listSettings() end
  name = name:lower():gsub("^chores%.", "")
  if DEFAULT[name] == nil then return info("red", "No setting called " .. name .. ". chores set lists them.") end
  if not value then
    local v = get(name)
    return info("white", name .. " = " .. (v == "" and "(empty)" or tostring(v)))
  end
  local lower = value:lower()
  if lower == "default" then
    C.set[name] = nil
  elseif lower == "off" or lower == "none" or lower == "clear" or value == '""' then
    if NUMERIC[name] then return info("red", name .. " is a number.") end
    C.set[name] = ""
  elseif NUMERIC[name] then
    local n = tonumber(value)
    if not n or n < 0 then return info("red", name .. " is a number (" .. tostring(DEFAULT[name]) .. " by default).") end
    C.set[name] = n
  else
    C.set[name] = value
  end
  if C.set[name] == DEFAULT[name] then C.set[name] = nil end
  C.save()
  local v = get(name)
  info("white", name .. " = " .. (v == "" and "(empty)" or tostring(v)))
end

function C.command(c, arg)
  c = c and c:lower()
  if c == "start" or c == "on" then
    local m = arg and arg:lower()
    if m and m ~= "fish" and m ~= "quest" and m ~= "both" then return info("red", "chores start fish, quest or both") end
    C.start(m)
  elseif c == "fish" or c == "quest" or c == "both" then C.start(c)
  elseif c == "stop" or c == "off" then
    if C.mode == "off" then info("white", "Already off.") else C.stop() end
  elseif c == "status" then C.status()
  elseif c == "set" or c == "settings" then
    local name, value = (arg or ""):match("^(%S+)%s*(.-)%s*$")
    if name == "" then name = nil end
    if value == "" then value = nil end
    C.setting(name, value)
  elseif c == "debug" and (arg == "on" or arg == "off") then
    C.debug = arg == "on"; C.save(); info("white", "Debug " .. arg)
  else C.help() end
end

-- ---------------------------------------------------------------- events
if type(registerNamedEventHandler) == "function" then
  registerNamedEventHandler("Chores", "chores disconnect", "sysDisconnectionEvent", C.disconnected)
  registerNamedEventHandler("Chores", "chores connect", "sysConnectionEvent", C.disconnected)
  registerNamedEventHandler("Chores", "chores uninstall", "sysUninstallPackage", function(_, name)
    if name == "Chores" then C.stop(true) end
  end)
end
