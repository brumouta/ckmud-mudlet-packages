-- BossTimer: reads the respawn from `uptime`, warns, re-checks quietly after respawns.
-- Run from the repo root: lua tests/BossTimer_test.lua
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
-- Geyser stand-ins for the window
local labelText
Adjustable = { Container = { new = function(_, o) return { Inside = {}, show = function() end, hide = function() end } end } }
Geyser = { Label = { new = function() return { setStyleSheet = function() end, echo = function(_, t) labelText = t end } end } }

dofile("packages/BossTimer/src/BossTimer.lua")

-- The game: feed lines through the package's triggers (same patterns as package.json)
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    line = l
    local ids = {}
    for i in pairs(temps) do ids[#ids + 1] = i end
    table.sort(ids)
    local started = l:match("^CKMud System Information:")
    for _, i in ipairs(ids) do if temps[i] then temps[i].f() end end   -- the gag matches every line ("^")
    if started then BossTimer.blockStart() end
    if l:find("Copyover recovery complete.", 1, true) then BossTimer.onCopyover() end
    local t = l:match("^%s*Boss Respawn:%s*(.-)%s*remaining")
    if t then BossTimer.onRespawnLine(t) end
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
ok(BossTimer.parse("16 min 35 sec") == 995 and BossTimer.parse("1 hour 2 min 3 sec") == 3723
   and BossTimer.parse("45 sec") == 45 and BossTimer.parse("2 hours") == 7200 and BossTimer.parse("soon") == nil,
   "reads hours, minutes and seconds")

-- Just installed mid-session: it doesn't know the respawn time, so it asks by itself
wait(5)
ok(sent[1] == "uptime", "installed mid-session: asks uptime 5 seconds after loading")
feed(UPTIME:format("20 min 0 sec"))
ok(deleted == 12 and math.abs(BossTimer.remaining() - 1200) < 0.01, "that check is hidden and the countdown starts")
sent, deleted = {}, 0

-- You type uptime: shown as normal, countdown starts
feed(UPTIME:format("16 min 35 sec"))
ok(deleted == 0, "an uptime you typed yourself stays on screen")
ok(math.abs(BossTimer.remaining() - 995) < 0.01, "countdown starts from the Boss Respawn line")
BossTimer.command(nil); ok(LOG:find("Bosses respawn in 16m 35s"), "`boss` shows the time left")

-- Warnings, the respawn, then a quiet re-check
LOG = ""
wait(995 - 300); ok(LOG:find("Bosses respawn in 5m 00s!"), "warns 5 minutes before")
wait(240);       ok(LOG:find("Bosses respawn in 1m 00s!"), "warns 1 minute before")
wait(60);        ok(LOG:find("Bosses have respawned!") and alerts == 1, "announces the respawn and flashes")
ok(math.abs(BossTimer.remaining() - 1200) < 0.01 and BossTimer.estimated, "the next respawn is assumed 20 minutes away")
LOG = ""; BossTimer.command(nil); ok(LOG:find("~20m 00s %(estimated"), "shown with a ~ until uptime confirms it")
sent = {}
wait(60);        ok(sent[1] == "uptime", "asks uptime a minute after the respawn")
deleted = 0
feed(UPTIME:format("59 min 0 sec") .. "\n[Pl: 1,000 | ...] next line after the block")
ok(deleted == 12, "that automatic uptime block (12 lines) is hidden, nothing after it")
ok(math.abs(BossTimer.remaining() - 3540) < 0.01 and not BossTimer.estimated, "uptime corrects the estimate to the exact time")

-- After logging in it checks by itself
sent = {}
handlers.sysConnectionEvent()
wait(10); ok(sent[1] == "uptime", "asks uptime 10 seconds after logging in")
feed(UPTIME:format("30 min 0 sec"))

-- Custom warnings re-arm the current countdown
LOG = ""
BossTimer.command("warn", "10,2")
wait(1800 - 600); ok(LOG:find("Bosses respawn in 10m 00s!"), "boss warn 10,2: warns at 10 minutes")
wait(480);        ok(LOG:find("Bosses respawn in 2m 00s!"), "and at 2 minutes")
ok(not LOG:find("in 5m 00s!"), "old warnings are gone")

-- Warning times: decimals, seconds, duplicates and zero
local function warns(text) local l = BossTimer.parseWarnings(text); return l and table.concat(l, ",") end
ok(warns("0.5") == "30", "boss warn 0.5 is 30 seconds")
ok(warns("5,0.5") == "300,30" and warns("1.5") == "90", "decimals mixed with whole minutes")
ok(warns("2,30s") == "120,30" and warns("10 2 30s") == "600,120,30", "seconds with s, spaces as separators")
ok(warns("5,5,1,0") == "300,60", "duplicates and zero are dropped")
ok(select(2, BossTimer.parseWarnings("5,abc")) == "abc", "anything else is rejected, with the bad piece named")
LOG = ""
BossTimer.command("warn", "5,abc"); ok(LOG:find("Didn't understand 'abc'"), "and nothing changes")
BossTimer.command("warn", "1,0.5"); ok(LOG:find("Warning at 1m 00s, 0m 30s before the respawn"), "the confirmation shows what was set")
feed(UPTIME:format("2 min 0 sec")); LOG = ""
wait(90); ok(LOG:find("Bosses respawn in 0m 30s!"), "a 0.5-minute warning fires 30 seconds before")
feed(UPTIME:format("2 min 0 sec"))              -- a fresh countdown for the window checks below

-- Window
BossTimer.command("window", "on")
ok(labelText and labelText:find("2m 00s"), "window shows the live countdown")
named.window = nil
BossTimer.command("window", "off")
ok(named.window == nil, "window off stops its refresh timer")

-- A copyover restarts the server: the old countdown is dropped and a fresh uptime is read
feed(UPTIME:format("40 min 0 sec"))
LOG, sent, deleted = "", {}, 0
feed("Copyover recovery complete.")
ok(math.abs(BossTimer.remaining() - 1200) < 0.01 and BossTimer.estimated and LOG:find("Server restarted %(copyover%)"),
   "copyover replaces the old countdown with an estimated 20 minutes")
wait(5); ok(sent[1] == "uptime", "it asks uptime 5 seconds after the copyover")
feed(UPTIME:format("59 min 50 sec"))
ok(deleted == 12 and math.abs(BossTimer.remaining() - 3590) < 0.01, "the new countdown starts, check hidden")
wait(40 * 60)                                  -- past when the old 40-minute countdown would have ended
ok(not LOG:find("Bosses respawn in") and not LOG:find("have respawned"), "the old countdown's warnings never fire")

-- While the respawn time is unknown it keeps asking (every 5 minutes), but only when it makes sense
BossTimer.respawnAt = nil
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
ok(math.abs(BossTimer.remaining() - 600) < 0.01, "and it's used for the countdown")
sent = {}
named.unknown(); ok(#sent == 0, "once it's known, the 5-minute check does nothing")

-- If uptime can't be checked after a respawn, the 20-minute estimate still warns
LOG, sent = "", {}
wait(600)                                      -- the 10-minute countdown above runs out: respawn
ok(LOG:find("Bosses have respawned!"), "respawned")
wait(BossTimer.answerWait + 60)                -- its uptime check goes unanswered (lag)
ok(BossTimer.estimated, "still on the estimate")
named.unknown(); ok(#sent == 2, "while it's only an estimate, the 5-minute check keeps asking")
wait(1200); ok(LOG:find("Bosses respawn in 1m 00s!") and LOG:find("Bosses respawn in 0m 30s!"),   -- set by boss warn 1,0.5 above
               "the estimate's warnings fire anyway (being a little off is fine)")

BossTimer.command("flash", "off"); BossTimer.command("help"); BossTimer.command("bogus")
print("\nBossTimer: ALL PASSED")
