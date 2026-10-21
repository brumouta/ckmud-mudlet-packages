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

-- ---------------------------------------------------------------- `boss` alias
BT.HELP = {
  { "boss",                 "Time left until the bosses respawn" },
  { "boss check",           "Ask `uptime` now (shown on screen)" },
  { "boss window on|off",   "A small window with a live countdown" },
  { "boss warn <min,...>",  "When to warn before the respawn, in minutes (5,1,0.5) or seconds (30s); default 5,1" },
  { "boss flash on|off",    "Flash Mudlet's taskbar icon at the respawn" },
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
  elseif cmd == "check" then
    BT.check(false)
  elseif cmd == "window" and (arg == "on" or arg == "off") then
    BT.showWindow(arg == "on")
  elseif cmd == "flash" and (arg == "on" or arg == "off") then
    BT.flash = arg == "on"
    info("white", "Flash " .. arg)
  elseif cmd == "warn" and arg then
    local list, bad = BT.parseWarnings(arg)
    if bad then return info("yellow", "Didn't understand '" .. bad .. "'. Use minutes like 5,1,0.5 or seconds like 30s") end
    BT.warnings = list
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
