-- BossHelpers: reads the respawn from `uptime`, warns, re-checks quietly after respawns.
-- Run from the repo root: lua tests/BossHelpers_test.lua
local now, timers, temps, handlers, nextId = 1000, {}, {}, {}, 0
local sent, deleted, alerts = {}, 0, 0
function getEpoch() return now end
function cecho(s) LOG = (LOG or "") .. s end
function send(c) sent[#sent + 1] = c end
function alert() alerts = alerts + 1 end
function deleteLine() deleted = deleted + 1 end
function tempTimer(d, f) nextId = nextId + 1; timers[nextId] = { at = now + d, f = f }; return nextId end
function killTimer(i) timers[i] = nil end
function tempRegexTrigger(p, f) nextId = nextId + 1; temps[nextId] = { p = p, f = f }; return nextId end
function killTrigger(i) temps[i] = nil end
function registerNamedEventHandler(_, name, event, fn) handlers[event] = fn end
local named = {}
function registerNamedTimer(_, name, _, fn) named[name] = fn end
local isConnected = true
function getConnectionInfo() return "ckmud", 4000, isConnected end
function deleteNamedTimer(_, name) named[name] = nil end
-- Saved settings live in memory
local files = {}
function getMudletHomeDir() return "/home" end
function io.exists(f) return files[f] ~= nil end
function table.save(f, t) local c = {}; for k, v in pairs(t) do c[k] = v end; files[f] = c end
function table.load(f, into) for k, v in pairs(files[f]) do into[k] = v end end
-- Geyser stand-ins for the window
local labelText, windows = nil, 0
Adjustable = { Container = { new = function(_, o) windows = windows + 1; return { Inside = {}, show = function() end, hide = function() end } end } }
Geyser = { Label = { new = function() return { setStyleSheet = function() end, echo = function(_, t) labelText = t end } end } }

dofile("packages/BossHelpers/src/BossHelpers.lua")

-- The game: feed lines through the package's triggers (same patterns as package.json)
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    line = l
    local ids = {}
    for i in pairs(temps) do ids[#ids + 1] = i end
    table.sort(ids)
    local started = l:match("^CKMud System Information:")
    for _, i in ipairs(ids) do if temps[i] then temps[i].f() end end   -- the gag matches every line ("^")
    if started then BossHelpers.blockStart() end
    if l:find("Copyover recovery complete.", 1, true) then BossHelpers.onCopyover() end
    local t = l:match("^%s*Boss Respawn:%s*(.-)%s*remaining")
    if t then BossHelpers.onRespawnLine(t) end
  end
end
local UPTIME = [[CKMud System Information:
o------------------------------------------------------------o
 Current Time:    12:20:55 PM Oct 21(Wed) 2026
 Last Reboot:     07:37:30 AM Oct 20(Tue) 2026
 Total Runtime:   1 day, 4 hours and 43 minutes

 Players:         38             Peak Players: 44
 Budokai Start:   08:00:00 PM (7PM CST)
 High Stakes:     Fri Oct 23 09:00:00 PM (8PM CST)

 Boss Respawn:    %s remaining
o------------------------------------------------------------o]]
local function wait(secs)
  local target = now + secs
  while true do
    local best, bestId
    for i, t in pairs(timers) do if t.at <= target and (not best or t.at < best.at) then best, bestId = t, i end end
    if not best then break end
    timers[bestId] = nil; now = best.at; best.f()
  end
  now = target
end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end

-- Parsing
ok(BossHelpers.parse("16 min 35 sec") == 995 and BossHelpers.parse("1 hour 2 min 3 sec") == 3723
   and BossHelpers.parse("45 sec") == 45 and BossHelpers.parse("2 hours") == 7200 and BossHelpers.parse("soon") == nil,
   "reads hours, minutes and seconds")

-- Just installed mid-session: it doesn't know the respawn time, so it asks by itself
wait(5)
ok(sent[1] == "uptime", "installed mid-session: asks uptime 5 seconds after loading")
feed(UPTIME:format("20 min 0 sec"))
ok(deleted == 12 and math.abs(BossHelpers.remaining() - 1200) < 0.01, "that check is hidden and the countdown starts")
sent, deleted = {}, 0

-- You type uptime: shown as normal, countdown starts
feed(UPTIME:format("16 min 35 sec"))
ok(deleted == 0, "an uptime you typed yourself stays on screen")
ok(math.abs(BossHelpers.remaining() - 995) < 0.01, "countdown starts from the Boss Respawn line")
BossHelpers.command(nil); ok(LOG:find("Bosses respawn in 16m 35s"), "`boss` shows the time left")

-- Warnings, the respawn, then a quiet re-check
LOG = ""
wait(995 - 300); ok(LOG:find("Bosses respawn in 5m 00s!"), "warns 5 minutes before")
wait(240);       ok(LOG:find("Bosses respawn in 1m 00s!"), "warns 1 minute before")
wait(60);        ok(LOG:find("Bosses have respawned!") and alerts == 1, "announces the respawn and flashes")
ok(math.abs(BossHelpers.remaining() - 1200) < 0.01 and BossHelpers.estimated, "the next respawn is assumed 20 minutes away")
LOG = ""; BossHelpers.command(nil); ok(LOG:find("~20m 00s %(estimated"), "shown with a ~ until uptime confirms it")
sent = {}
wait(60);        ok(sent[1] == "uptime", "asks uptime a minute after the respawn")
deleted = 0
feed(UPTIME:format("59 min 0 sec") .. "\n[Pl: 1,000 | ...] next line after the block")
ok(deleted == 12, "that automatic uptime block (12 lines) is hidden, nothing after it")
ok(math.abs(BossHelpers.remaining() - 3540) < 0.01 and not BossHelpers.estimated, "uptime corrects the estimate to the exact time")

-- After logging in it checks by itself
sent = {}
handlers.sysConnectionEvent()
wait(10); ok(sent[1] == "uptime", "asks uptime 10 seconds after logging in")
feed(UPTIME:format("30 min 0 sec"))

-- Custom warnings re-arm the current countdown
LOG = ""
BossHelpers.command("warn", "10,2")
wait(1800 - 600); ok(LOG:find("Bosses respawn in 10m 00s!"), "boss warn 10,2: warns at 10 minutes")
wait(480);        ok(LOG:find("Bosses respawn in 2m 00s!"), "and at 2 minutes")
ok(not LOG:find("in 5m 00s!"), "old warnings are gone")

-- Warning times: decimals, seconds, duplicates and zero
local function warns(text) local l = BossHelpers.parseWarnings(text); return l and table.concat(l, ",") end
ok(warns("0.5") == "30", "boss warn 0.5 is 30 seconds")
ok(warns("5,0.5") == "300,30" and warns("1.5") == "90", "decimals mixed with whole minutes")
ok(warns("2,30s") == "120,30" and warns("10 2 30s") == "600,120,30", "seconds with s, spaces as separators")
ok(warns("5,5,1,0") == "300,60", "duplicates and zero are dropped")
ok(select(2, BossHelpers.parseWarnings("5,abc")) == "abc", "anything else is rejected, with the bad piece named")
LOG = ""
BossHelpers.command("warn", "5,abc"); ok(LOG:find("Didn't understand 'abc'"), "and nothing changes")
BossHelpers.command("warn", "1,0.5"); ok(LOG:find("Warning at 1m 00s, 0m 30s before the respawn"), "the confirmation shows what was set")
feed(UPTIME:format("2 min 0 sec")); LOG = ""
wait(90); ok(LOG:find("Bosses respawn in 0m 30s!"), "a 0.5-minute warning fires 30 seconds before")
feed(UPTIME:format("2 min 0 sec"))              -- a fresh countdown for the window checks below

-- Window
BossHelpers.command("window", "on")
ok(labelText and labelText:find("2m 00s"), "window shows the live countdown")
named.window = nil
BossHelpers.command("window", "off")
ok(named.window == nil, "window off stops its refresh timer")


-- A copyover restarts the server: the old countdown is dropped and a fresh uptime is read
feed(UPTIME:format("40 min 0 sec"))
LOG, sent, deleted = "", {}, 0
feed("Copyover recovery complete.")
ok(math.abs(BossHelpers.remaining() - 1200) < 0.01 and BossHelpers.estimated and LOG:find("Server restarted %(copyover%)"),
   "copyover replaces the old countdown with an estimated 20 minutes")
wait(5); ok(sent[1] == "uptime", "it asks uptime 5 seconds after the copyover")
feed(UPTIME:format("59 min 50 sec"))
ok(deleted == 12 and math.abs(BossHelpers.remaining() - 3590) < 0.01, "the new countdown starts, check hidden")
wait(40 * 60)                                  -- past when the old 40-minute countdown would have ended
ok(not LOG:find("Bosses respawn in") and not LOG:find("have respawned"), "the old countdown's warnings never fire")

-- While the respawn time is unknown it keeps asking (every 5 minutes), but only when it makes sense
BossHelpers.respawnAt = nil
sent = {}
isConnected = false
named.unknown(); ok(#sent == 0, "unknown but disconnected: doesn't ask")
isConnected = true
named.unknown(); ok(sent[1] == "uptime", "unknown and connected: asks")
named.unknown(); ok(#sent == 1, "doesn't ask again while that check is still pending")
-- That check is never answered (lag): after 15 seconds it gives up...
wait(15)
deleted = 0
feed(UPTIME:format("10 min 0 sec"))
ok(deleted == 0, "...so an uptime you then type yourself is still shown")
ok(math.abs(BossHelpers.remaining() - 600) < 0.01, "and it's used for the countdown")
sent = {}
named.unknown(); ok(#sent == 0, "once it's known, the 5-minute check does nothing")

-- If uptime can't be checked after a respawn, the 20-minute estimate still warns
LOG, sent = "", {}
wait(600)                                      -- the 10-minute countdown above runs out: respawn
ok(LOG:find("Bosses have respawned!"), "respawned")
wait(BossHelpers.answerWait + 60)                -- its uptime check goes unanswered (lag)
ok(BossHelpers.estimated, "still on the estimate")
named.unknown(); ok(#sent == 2, "while it's only an estimate, the 5-minute check keeps asking")
wait(1200); ok(LOG:find("Bosses respawn in 1m 00s!") and LOG:find("Bosses respawn in 0m 30s!"),   -- set by boss warn 1,0.5 above
               "the estimate's warnings fire anyway (being a little off is fine)")

BossHelpers.command("flash", "off"); BossHelpers.command("help"); BossHelpers.command("bogus")
-- Settings survive a restart: a fresh Mudlet session loads the package with nothing in memory
local function restart()
  BossHelpers, BossTimer, named, windows, labelText = nil, nil, {}, 0, nil
  for k in pairs(timers) do timers[k] = nil end            -- a restart drops every timer
  dofile("packages/BossHelpers/src/BossHelpers.lua")
end
BossHelpers.command("window", "on"); BossHelpers.command("flash", "off"); BossHelpers.command("warn", "10,2")
restart()
ok(BossHelpers.windowOn and windows == 1 and named.window, "window on is back after a restart, refreshing")
ok(BossHelpers.flash == false and table.concat(BossHelpers.warnings, ",") == "600,120", "flash and warnings are back too")
BossHelpers.command("window", "off")
restart()
ok(not BossHelpers.windowOn and windows == 0, "window off stays off after a restart")

-- boss find: walk to the 👹 on the world map, from real maps
local MAPS, cur = {}, nil
for l in io.lines("tests/fixtures/bossfind.log") do
  local name = l:match("^## (.+)$")
  if name then cur = name; MAPS[cur] = {} elseif cur then table.insert(MAPS[cur], l) end
end
local function show(name) for _, l in ipairs(MAPS[name]) do BossHelpers.line(l) end end
local function rows(name) local r, on = {}, false
  for _, l in ipairs(MAPS[name]) do
    if l:match("^%s*o%-%-%-") then on = not on elseif on then r[#r + 1] = l end
  end
  return r end
local b = BossHelpers.readMap(rows("far"))[1]
ok(b[1] == -1 and b[2] == -1, "boss one west, one north (got " .. b[1] .. "," .. b[2] .. ")")
b = BossHelpers.readMap(rows("south"))[1]
ok(b[1] == 0 and b[2] == 1, "boss right below")
b = BossHelpers.readMap(rows("east"))[1]
ok(b[1] == 1 and b[2] == 0, "boss right next to me, east")
ok(#BossHelpers.readMap(rows("on")) == 0, "standing on the boss: no 👹 drawn")
-- the walk
sent = {}
BossHelpers.command("find"); ok(sent[#sent] == "look", "find looks first")
show("south"); ok(sent[#sent] == "s", "walks south: " .. tostring(sent[#sent]))
LOG = ""; show("on"); ok(LOG:find("You're on the boss"), "arrived")
ok(BossHelpers.hunt == nil, "done")
-- far away: dash, wait for it to finish, look again
BossHelpers.command("find"); sent = {}
local far = {}
for i = 1, 6 do far[i] = "   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ " end
far[2] = "   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ 👹~ ~ "
far[4] = "   ~ ~ ~ 🧍~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ "
local function feedMap(r) BossHelpers.line("o----------------o"); for _, l in ipairs(r) do BossHelpers.line(l) end; BossHelpers.line("o----------------o") end
feedMap(far); ok(sent[#sent] == "dash e", "far east: dash (" .. tostring(sent[#sent]) .. ")")
feedMap(far); ok(#sent == 1, "maps shown during the dash are ignored")
BossHelpers.line("You fly quickly through the area!"); ok(sent[#sent] == "look", "looks again after the dash")
BossHelpers.command("find", "stop"); ok(BossHelpers.hunt == nil, "find stop")
-- nothing in sight: north-west corner, then sweep east / south / west / south ...
local empty = { far[1], far[4] }
local BLOCK = "Alas, you cannot go that way...\nYour dash is halted by an obstacle.\nYou can't dash in that direction.\n[Pl: 152,065,671,629 100% | Ki: 100% | Fatigue: 1%]"
local function say(text) for l in (text .. "\n"):gmatch("(.-)\n") do BossHelpers.line(l) end end
local DONE = "You fly quickly through the area!"
local SHORT = "Alas, you cannot go that way...\nYour dash is halted by an obstacle.\nYou fly quickly through the area!\n[Pl: 1 100% | Ki: 100%]"
LOG = ""; BossHelpers.command("find"); sent = {}
feedMap(empty); ok(sent[#sent] == "dash n" and LOG:find("No 👹 in sight"), "nothing in sight: dash north")
feedMap(empty); say(DONE); ok(sent[#sent] == "dash n", "keeps going north")
say(BLOCK); ok(sent[#sent] == "dash w" and #sent == 3, "north edge: west (once, for the three lines)")
say(DONE); ok(sent[#sent] == "dash w", "keeps going west")
say(SHORT); ok(sent[#sent] == "dash e" and #sent == 5 and LOG:find("In the corner"), "stopped short at the edge: one stop, sweep east")
say(DONE); ok(sent[#sent] == "dash e", "east")
say(BLOCK); ok(sent[#sent] == "dash s", "east edge: 10 south")
say(DONE); ok(sent[#sent] == "dash w", "then back west")
say(SHORT); ok(sent[#sent] == "dash s", "west edge: south again")
say(SHORT); ok(sent[#sent] == "dash e" and BossHelpers.hunt, "went part way south: sweep that last row too")
say(SHORT); ok(BossHelpers.hunt == nil and LOG:find("Swept the whole map"), "last row done: nothing anywhere")
-- a south dash that can't move at all means the row before was the last one
LOG = ""; BossHelpers.command("find"); feedMap(empty); sent = {}
say(BLOCK); say(BLOCK); say(BLOCK); ok(sent[#sent] == "dash s", "north, west, east edges")
say(BLOCK); ok(BossHelpers.hunt == nil and LOG:find("Swept the whole map"), "can't go south: done")
-- a 👹 goes by during the sweep: look once the dash ends, then walk to it
BossHelpers.command("find"); feedMap(empty); sent = {}
say(DONE); ok(sent[#sent] == "dash n", "searching")
feedMap({ far[2], far[4] }); ok(#sent == 1 and LOG:find("spotted"), "spotted mid-dash: nothing sent yet")
say(DONE); ok(sent[#sent] == "look", "dash over: look")
show("south"); ok(sent[#sent] == "s", "and walk to it")
show("on"); ok(BossHelpers.hunt == nil, "there")

print("\nBossHelpers: ALL PASSED")
