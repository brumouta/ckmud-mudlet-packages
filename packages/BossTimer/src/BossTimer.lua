-- BossTimer: counts down to CKMud's boss respawn. Type `boss help` for commands.
--
-- `uptime` prints "Boss Respawn: 16 min 35 sec remaining". This package turns that
-- into a countdown, warns before the respawn, and re-checks `uptime` by itself after
-- each respawn (and after you log in) so the next countdown starts on its own.
BossTimer = BossTimer or {}
local BT = BossTimer

-- ---------------------------------------------------------------- settings
BT.warnings   = BT.warnings or { 300, 60 }  -- seconds before the respawn to warn at
BT.cycle      = 1200                        -- bosses respawn about every 20 minutes (assumed until uptime says)
BT.recheck    = 60                          -- seconds after a respawn to ask `uptime` again
BT.afterLogin = 10                          -- seconds after connecting to ask `uptime`
BT.afterCopyover = 5                        -- seconds after a copyover to ask `uptime`
BT.unknownRetry = 300                       -- while the respawn time is unknown, ask `uptime` this often
BT.answerWait = 15                          -- an automatic check not answered by then is given up
BT.flash      = (BT.flash == nil) and true or BT.flash   -- flash Mudlet's taskbar icon at respawn

-- ---------------------------------------------------------------- state
BT.respawnAt = BT.respawnAt or nil          -- epoch of the next respawn
BT._timers   = BT._timers or {}

local function info(color, msg) cecho("\n<" .. color .. ">[Boss] " .. msg .. "\n") end

function BT.fmt(secs)
  secs = math.max(0, math.floor(secs + 0.5))
  local h, m, s = math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60
  if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
  return string.format("%dm %02ds", m, s)
end

function BT.remaining()
  return BT.respawnAt and (BT.respawnAt - getEpoch()) or nil
end

-- "16 min 35 sec", "1 hour 2 min", "45 sec", "2 hours" ... -> seconds
function BT.parse(text)
  local total, found = 0, false
  for n, unit in text:lower():gmatch("(%d+)%s*(%a+)") do
    local mult = unit:match("^h") and 3600 or unit:match("^m") and 60 or unit:match("^s") and 1
    if mult then
      total, found = total + tonumber(n) * mult, true
    end
  end
  return found and total or nil
end

local function clearTimers()
  for _, id in ipairs(BT._timers) do killTimer(id) end
  BT._timers = {}
end

local function at(secsFromNow, fn)
  if secsFromNow >= 0 then BT._timers[#BT._timers + 1] = tempTimer(secsFromNow, fn) end
end

-- ---------------------------------------------------------------- the countdown
-- Count down `secs` to the next respawn, with warnings. estimated = assumed (20 minutes
-- after a respawn or copyover) rather than read from `uptime`; it's shown with a "~".
function BT.startCountdown(secs, estimated)
  BT.respawnAt = getEpoch() + secs
  BT.estimated = estimated or false
  clearTimers()
  for _, w in ipairs(BT.warnings) do
    if secs > w then
      at(secs - w, function() info("yellow", "Bosses respawn in " .. BT.fmt(w) .. "!") end)
    end
  end
  at(secs, BT.respawned)
  BT.refresh()
end

-- Called by the trigger on "Boss Respawn: <time> remaining": the exact time
function BT.onRespawnLine(text)
  local secs = BT.parse(text)
  if not secs then return end
  BT.checkingAt = nil
  BT.startCountdown(secs, false)
end

function BT.respawned()
  info("green", "Bosses have respawned!")
  if BT.flash then alert(10) end
  BT.startCountdown(BT.cycle, true)              -- the next one is about 20 minutes away...
  at(BT.recheck, function() BT.check(true) end)  -- ...uptime will say exactly
end

-- ---------------------------------------------------------------- asking `uptime`
-- quiet = hide the uptime block on screen (automatic checks)
function BT.check(quiet)
  BT.quiet = quiet or false
  BT.checkingAt = getEpoch()
  send("uptime", false)
  -- If it's never answered (lag, a disconnect), stop waiting: otherwise the next
  -- uptime you type yourself would be hidden
  if BT._answerTimer then killTimer(BT._answerTimer) end
  BT._answerTimer = tempTimer(BT.answerWait, function()
    BT._answerTimer = nil
    if not BT._gag then BT.quiet = false end
    BT.checkingAt = nil
  end)
end

local function connected()
  local ok, _, _, isConnected = pcall(getConnectionInfo)
  if ok and isConnected ~= nil then return isConnected end
  return true                                -- older Mudlet without getConnectionInfo
end

-- Ask quietly whenever the respawn time is unknown or only estimated: after installing
-- or reloading the package, after a check that went unanswered, ... (not while one is pending)
function BT.ensureKnown()
  if (BT.respawnAt and not BT.estimated) or BT.checkingAt or not connected() then return end
  BT.check(true)
end

-- The uptime block runs from "CKMud System Information:" to its second border line.
-- When the check was automatic, hide every line of it (the triggers still read them).
function BT.blockStart()
  if not BT.quiet then return end
  if BT._answerTimer then killTimer(BT._answerTimer); BT._answerTimer = nil end
  deleteLine()
  local borders = 0
  if BT._gag then killTrigger(BT._gag) end
  BT._gag = tempRegexTrigger("^", function()
    deleteLine()
    if line:match("^o%-+o$") then
      borders = borders + 1
      if borders == 2 then
        killTrigger(BT._gag)
        BT._gag, BT.quiet = nil, false
      end
    end
  end)
end

-- "Copyover recovery complete.": the server restarted, so uptime and the respawn timer
-- started over. Drop the old countdown and read the new one.
function BT.onCopyover()
  info("white", "Server restarted (copyover) - boss respawn in about 20 minutes, checking uptime")
  BT.startCountdown(BT.cycle, true)
  at(BT.afterCopyover, function() BT.check(true) end)
end

registerNamedEventHandler("BossTimer", "login", "sysConnectionEvent", function()
  at(BT.afterLogin, function() BT.check(true) end)
end)

registerNamedTimer("BossTimer", "unknown", BT.unknownRetry, BT.ensureKnown, true)
tempTimer(5, BT.ensureKnown)                -- just installed or reloaded mid-session

-- ---------------------------------------------------------------- window
function BT.showWindow(show)
  if show and not BT.container then
    BT.container = Adjustable.Container:new({
      name = "Boss Respawn", x = "70%", y = "40%", width = "230px", height = "60px",
      titleText = "Boss Respawn",
    })
    BT.label = Geyser.Label:new({ name = "BossTimerLabel", x = 0, y = 0, width = "100%", height = "100%" },
      BT.container.Inside)
    BT.label:setStyleSheet("background-color: #0a0a0a; qproperty-alignment: 'AlignCenter';")
  end
  if BT.container then
    if show then BT.container:show() else BT.container:hide() end
  end
  BT.windowOn = show
  if show then
    registerNamedTimer("BossTimer", "window", 1, BT.refresh, true)
  else
    deleteNamedTimer("BossTimer", "window")
  end
  BT.refresh()
end

function BT.refresh()
  if not (BT.windowOn and BT.label) then return end
  local left = BT.remaining()
  local text, color
  if not left then
    text, color = "unknown - type uptime", "grey"
  else
    text = (BT.estimated and "~" or "") .. BT.fmt(left)
    color = left <= 60 and "red" or left <= 300 and "orange" or "lime"
  end
  BT.label:echo("<center><font size=5 color='" .. color .. "'>" .. text .. "</font></center>")
end

-- ---------------------------------------------------------------- saved settings
-- The window, the warnings and the flash survive restarts (the window's place and size
-- are saved by Mudlet's Adjustable.Container itself).
BT.SAVE_FILE = getMudletHomeDir() .. "/BossTimer.lua"

function BT.save()
  pcall(table.save, BT.SAVE_FILE, { window = BT.windowOn or false, warnings = BT.warnings, flash = BT.flash })
end

function BT.load()
  local saved = {}
  if not (io.exists(BT.SAVE_FILE) and pcall(table.load, BT.SAVE_FILE, saved)) then return end
  if type(saved.warnings) == "table" then BT.warnings = saved.warnings end
  if saved.flash ~= nil then BT.flash = saved.flash end
  if saved.window then BT.showWindow(true) end
end

-- ---------------------------------------------------------------- finding a boss on the map
-- `boss find`: walk to the nearest 👹 on the world map (for bosses `pursue` can't reach).
-- The room map is drawn between two "o----o" lines with you as 🧍. Each map cell is two
-- columns wide (an emoji, or two plain characters like "▒░" / "~ "), so the boss's offset
-- is (column difference / 2, row difference). Far away it dashes (10 rooms), close it walks.
BT.dashCmd   = BT.dashCmd or "dash %s"   -- how to dash in a direction
BT.dashFrom  = BT.dashFrom or 10         -- dash when the boss is at least this many rooms away
BT.findSteps = BT.findSteps or 40        -- give up after this many moves towards a boss
BT.searchDashes = BT.searchDashes or 150 -- give up searching after this many dashes
BT.ME, BT.BOSS = "🧍", "👹"

local WIDE = { [0x2757] = true, [0x2753] = true, [0x2754] = true, [0x2755] = true, [0x2B50] = true,
  [0x2B55] = true, [0x26A1] = true, [0x26D4] = true, [0x26EA] = true, [0x26F2] = true, [0x26F3] = true,
  [0x26F5] = true, [0x26FA] = true, [0x26FD] = true, [0x2705] = true, [0x274C] = true, [0x2728] = true,
  [0x231A] = true, [0x231B] = true, [0x23F0] = true, [0x23F3] = true, [0x2614] = true, [0x2615] = true }

-- The screen column each character starts at: { {col, char}, ... }
function BT.cells(line)
  local out, col, i = {}, 0, 1
  while i <= #line do
    local b = line:byte(i)
    local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
    local ch = line:sub(i, i + len - 1)
    local cp = b
    if len == 2 then cp = (b % 32) * 64 + line:byte(i + 1) % 64
    elseif len == 3 then cp = (b % 16) * 4096 + (line:byte(i + 1) % 64) * 64 + line:byte(i + 2) % 64
    elseif len == 4 then cp = (b % 8) * 262144 + (line:byte(i + 1) % 64) * 4096 + (line:byte(i + 2) % 64) * 64 + line:byte(i + 3) % 64 end
    local w = (cp == 0xFE0F or cp == 0x200D) and 0 or (cp >= 0x1F000 or WIDE[cp]) and 2 or 1
    out[#out + 1] = { col, ch }
    col = col + w
    i = i + len
  end
  return out
end

-- Where 🧍 and every 👹 are in a map (a list of rows): me = {x, y}, bosses = { {dx, dy}, ... }
function BT.readMap(rows)
  local me, found = nil, {}
  for y, row in ipairs(rows) do
    for _, c in ipairs(BT.cells(row)) do
      if c[2] == BT.ME then me = { c[1], y }
      elseif c[2] == BT.BOSS then found[#found + 1] = { c[1], y } end
    end
  end
  if not me then return nil end
  local bosses = {}
  for _, b in ipairs(found) do
    bosses[#bosses + 1] = { math.floor((b[1] - me[1]) / 2 + 0.5), b[2] - me[2] }
  end
  table.sort(bosses, function(a, b)
    return math.abs(a[1]) + math.abs(a[2]) < math.abs(b[1]) + math.abs(b[2])
  end)
  return bosses
end

-- Map capture: every line is offered; "o---o" borders open and close a map.
local mapRows
function BT.line(l)
  if l:match("^%s*o%-%-%-%-%-%-%-%-%-%-+o%s*$") then
    if mapRows and #mapRows > 0 then
      local bosses = BT.readMap(mapRows)
      if bosses then mapRows = nil; return BT.onMap(bosses) end
    end
    mapRows = {}                       -- (a border with no 🧍 inside starts again)
  elseif mapRows then
    mapRows[#mapRows + 1] = l
    if #mapRows > 25 then mapRows = nil end
  end
  local h = BT.hunt
  -- a stopped dash says up to three things ("Alas, you cannot go that way...", "Your dash is halted
  -- by an obstacle.", "You can't dash in that direction."): one stop, not three
  local blocked = l:find("You can't dash in that direction", 1, true) or l:find("Your dash is halted by an obstacle", 1, true)
    or l:find("Alas, you cannot go that way", 1, true)
  if h and blocked and h.justBlocked then return end
  if h then h.justBlocked = false end
  if h and h.dashing then
    if l:find("quickly through the area", 1, true) then BT.dashDone(true)
    elseif blocked then h.justBlocked = true; BT.dashDone(false) end
  elseif h and h.walking and l:find("Alas, you cannot go that way", 1, true) then
    BT.stopHunt("yellow", "Something's in the way, couldn't walk on")
  end
end

local function dist(b) return math.max(math.abs(b[1]), math.abs(b[2])) end

function BT.stopHunt(color, msg)
  local h = BT.hunt
  if h and h.timer then killTimer(h.timer) end
  BT.hunt = nil
  if msg then info(color, msg) end
end

local function huntTimeout()
  local h = BT.hunt
  if h.timer then killTimer(h.timer) end
  h.timer = tempTimer(15, function()
    if BT.hunt == h then BT.stopHunt("yellow", "Stopped looking: no answer to the last move") end
  end)
end

local function dash(dir)
  local h = BT.hunt
  h.dashing, h.walking, h.moves = true, false, h.moves + 1
  send(BT.dashCmd:format(dir))
  huntTimeout()
end

-- Searching, when no 👹 is in sight: dash north to the edge, then west (the north-west corner),
-- then sweep: east to the edge, 10 rooms south, west to the edge, 10 south... The map shows 5 rows
-- above and below you, so 10-room strips miss nothing. Any 👹 seen on the way ends the search.
local OPP = { e = "w", w = "e" }
function BT.searchNext(ok)
  local h = BT.hunt
  if h.moves >= BT.searchDashes then return BT.stopHunt("yellow", "Searched " .. h.moves .. " dashes without finding a boss") end
  local st = h.stage
  if st == "north" then
    if ok then return dash("n") end
    h.stage = "west"; return dash("w")
  elseif st == "west" then
    if ok then return dash("w") end
    h.stage, h.dir = "sweep", "e"; info("white", "In the corner: sweeping the map"); return dash("e")
  elseif st == "sweep" then
    if ok then return dash(h.dir) end
    h.stage = "down"; return dash("s")
  elseif st == "down" then
    if not ok then return BT.stopHunt("yellow", "Swept the whole map: no " .. BT.BOSS .. " anywhere") end
    h.stage, h.dir = "sweep", OPP[h.dir]; return dash(h.dir)
  end
end

-- A dash finished: on (ok) or stopped at an edge / obstacle
function BT.dashDone(ok)
  local h = BT.hunt
  h.dashing = false
  if h.mode == "search" and not h.spotted then return BT.searchNext(ok) end
  -- approaching, or a 👹 went by during the search: look where we are now
  h.mode, h.spotted = "approach", false
  send("look")
  huntTimeout()
end

function BT.onMap(bosses)
  local h = BT.hunt
  if not h then return end
  if h.dashing then
    if h.mode == "search" and bosses[1] and not h.spotted then h.spotted = true; info("green", BT.BOSS .. " spotted!") end
    return
  end
  local b = bosses[1]
  if not b then
    if h.last and dist(h.last) <= 1 then return BT.stopHunt("green", "You're on the boss: it's in this room") end
    if h.mode == "search" or h.searched then
      return BT.stopHunt("yellow", "Lost sight of the boss")
    end
    -- nothing in sight: search the map
    info("white", "No " .. BT.BOSS .. " in sight: heading for the north-west corner, then sweeping the map")
    h.mode, h.stage, h.searched = "search", "north", true
    return dash("n")
  end
  if h.steps >= BT.findSteps then return BT.stopHunt("yellow", "Gave up after " .. h.steps .. " moves") end
  local dx, dy = b[1], b[2]
  if h.steps == 0 then
    info("white", BT.BOSS .. " " .. math.abs(dy) .. (dy < 0 and " north" or " south") .. ", " ..
      math.abs(dx) .. (dx < 0 and " west" or " east") .. ": on the way")
  end
  local dir, n
  if math.abs(dx) >= math.abs(dy) then dir, n = dx > 0 and "e" or "w", math.abs(dx)
  else dir, n = dy > 0 and "s" or "n", math.abs(dy) end
  h.last, h.steps = b, h.steps + 1
  if n >= BT.dashFrom then return dash(dir) end
  h.walking = true
  send(dir)
  huntTimeout()
end

function BT.find()
  BT.stopHunt()
  BT.hunt = { mode = "approach", moves = 0, steps = 0 }
  send("look")
  huntTimeout()
end

-- ---------------------------------------------------------------- `boss` alias
BT.HELP = {
  { "boss",                 "Time left until the bosses respawn" },
  { "boss check",           "Ask `uptime` now (shown on screen)" },
  { "boss window on|off",   "A small window with a live countdown" },
  { "boss warn <min,...>",  "When to warn before the respawn, in minutes (5,1,0.5) or seconds (30s); default 5,1" },
  { "boss flash on|off",    "Flash Mudlet's taskbar icon at the respawn" },
  { "boss find",            "Walk to the nearest boss (👹) on the world map; none in sight: sweep the map with dash" },
  { "boss find stop",       "Stop walking" },
  { "boss help",            "Show this list" },
}

-- "5,1,0.5" or "10 2 30s" -> seconds, largest first, without duplicates or zero.
-- Plain numbers are minutes (decimals use a dot); a trailing s means seconds.
-- Returns nil plus the offending piece if something isn't a number.
function BT.parseWarnings(text)
  local list, seen = {}, {}
  for piece in text:gmatch("[^,%s]+") do
    local num, unit = piece:lower():match("^(%d*%.?%d+)([ms]?)$")
    if not num then return nil, piece end
    local secs = math.floor(tonumber(num) * (unit == "s" and 1 or 60) + 0.5)
    if secs > 0 and not seen[secs] then
      seen[secs] = true
      list[#list + 1] = secs
    end
  end
  table.sort(list, function(a, b) return a > b end)
  return list
end

function BT.command(cmd, arg)
  if cmd == nil then
    local left = BT.remaining()
    if left then
      info("white", "Bosses respawn in " .. (BT.estimated and ("~" .. BT.fmt(left) .. " (estimated, uptime not checked yet)") or BT.fmt(left)))
    else
      info("white", "Respawn time unknown - type uptime (or boss check)")
    end
  elseif cmd == "help" then
    cecho("\n<cyan>Boss respawn timer (boss) commands:\n")
    for _, row in ipairs(BT.HELP) do cecho(string.format("  <yellow>%-22s<white>%s\n", row[1], row[2])) end
  elseif cmd == "find" then
    if arg == "stop" then
      return BT.stopHunt("white", "Stopped looking")
    end
    BT.find()
  elseif cmd == "check" then
    BT.check(false)
  elseif cmd == "window" and (arg == "on" or arg == "off") then
    BT.showWindow(arg == "on")
    BT.save()
  elseif cmd == "flash" and (arg == "on" or arg == "off") then
    BT.flash = arg == "on"
    BT.save()
    info("white", "Flash " .. arg)
  elseif cmd == "warn" and arg then
    local list, bad = BT.parseWarnings(arg)
    if bad then return info("yellow", "Didn't understand '" .. bad .. "'. Use minutes like 5,1,0.5 or seconds like 30s") end
    BT.warnings = list
    BT.save()
    local shown = {}
    for _, w in ipairs(list) do shown[#shown + 1] = BT.fmt(w) end
    info("white", #list > 0 and ("Warning at " .. table.concat(shown, ", ") .. " before the respawn")
                             or "No warnings (the respawn itself is still announced)")
    local left = BT.remaining()
    if left then BT.onRespawnLine(math.floor(left) .. " sec") end   -- re-arm with the new warnings
  else
    info("yellow", "Unknown command. Type boss help")
  end
end

BT.load()
