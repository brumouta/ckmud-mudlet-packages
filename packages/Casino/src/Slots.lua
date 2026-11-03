-- Slot machine bot. Type `sl help` for commands.
--
-- Pulls the lever every few seconds and keeps score from your zenni (MSDP), so it doesn't
-- depend on the wording of the reels. Slots have no strategy: the only choices are how
-- many lines to play and when to stop.
sl = sl or {}
local SL = sl

-- ---------------------------------------------------------------- settings
SL.lines    = SL.lines or 5      -- lines per pull (1-5); each line is another bet
SL.delay    = SL.delay or 4      -- seconds between pulls, so the reels finish showing
SL.maxPulls = SL.maxPulls or 0   -- stop after this many pulls (0 = no limit)
SL.stopLoss = SL.stopLoss or 0   -- stop once down this much zenni (0 = no limit)
SL.target   = SL.target or 0     -- stop once up this much zenni (0 = no limit)
SL.keep     = SL.keep or 0       -- stop before your zenni drops below this
SL.stuck    = 3                  -- pulls in a row that don't change your zenni before stopping

-- ---------------------------------------------------------------- state
SL.active = false
local function newStats()
  return { pulls = 0, wins = 0, startZenni = nil, zenni = nil, best = 0, tails = 0, xp = 0 }
end
SL.stats = SL.stats or newStats()
local timer, lastZenni, unchanged

local info = casino.logger("sl")
local fmt, signed = casino.fmt, casino.signed

local function zenni()
  local z = rawget(_G, "MSDP") and MSDP.Player and MSDP.Player.Zenni
  return type(z) == "number" and z or nil
end

local function net()
  local s = SL.stats
  if s.zenni and s.startZenni then return s.zenni - s.startZenni end
end

-- ---------------------------------------------------------------- pulling
-- The zenni change since the last pull is that pull's result (its bet and anything it paid)
local function settle()
  local z = zenni()
  if not (z and lastZenni) then return end
  local delta = z - lastZenni
  local s = SL.stats
  s.zenni = z
  if delta == 0 then
    unchanged = unchanged + 1
  else
    unchanged = 0
    if delta > 0 then
      s.wins = s.wins + 1
      if delta > s.best then s.best = delta end
      info("green", "Won " .. fmt(delta) .. " zenni   <grey>pull " .. s.pulls .. ", net " .. signed(net()))
    end
  end
end

local function why()
  local s, n = SL.stats, net()
  if SL.maxPulls > 0 and s.pulls >= SL.maxPulls then return "played " .. s.pulls .. " pulls" end
  if n and SL.stopLoss > 0 and n <= -SL.stopLoss then return "stop loss reached (" .. signed(n) .. ")" end
  if n and SL.target > 0 and n >= SL.target then return "target reached (" .. signed(n) .. ")" end
  if SL.keep > 0 and s.zenni and s.zenni < SL.keep then return "zenni below " .. fmt(SL.keep) end
  if unchanged >= SL.stuck then
    return "your zenni didn't change for " .. unchanged .. " pulls - not at a machine, or out of zenni?"
  end
end

function SL.pull()
  timer = nil
  if not SL.active then return end
  settle()
  local reason = why()
  if reason then return SL.stop(reason) end
  lastZenni = zenni()
  SL.stats.pulls = SL.stats.pulls + 1
  send("pull " .. SL.lines, false)
  timer = tempTimer(SL.delay, SL.pull)
end

function SL.start()
  if SL.active then return info("yellow", "Already pulling (sl stop to stop)") end
  local z = zenni()
  if not z then
    info("yellow", "No zenni from MSDP: no stop loss, target or win tracking" ..
      (SL.maxPulls == 0 and " - and no pull limit, so stop it yourself with sl stop" or ""))
  end
  SL.active, unchanged = true, 0
  SL.stats.startZenni, SL.stats.zenni = z, z
  info("green", string.format("Pulling %d line%s every %ss. sl stop to stop.", SL.lines, SL.lines == 1 and "" or "s", SL.delay))
  SL.pull()
end

function SL.stop(reason)
  if timer then killTimer(timer); timer = nil end
  local was = SL.active
  SL.active = false
  if was then settle() end
  if reason then info("yellow", "Stopped: " .. reason) elseif was then info("yellow", "Bot OFF") end
  if was then SL.status() end
end

-- Credited by the casino core while the bot plays
function SL.luckyTails(n) SL.stats.tails = SL.stats.tails + n end
function SL.xpGained(n) SL.stats.xp = SL.stats.xp + n end

-- ---------------------------------------------------------------- `sl` alias
SL.HELP = {
  { "sl start",            "Start pulling (stand at a slot machine first)" },
  { "sl stop",             "Stop pulling" },
  { "sl status",           "Pulls, winning pulls, zenni net, best win, Lucky Tails, STR XP" },
  { "sl lines <1-5>",      "Lines per pull (default 5); each line costs another bet" },
  { "sl delay <secs>",     "Seconds between pulls (default 4)" },
  { "sl pulls <n>",        "Stop after n pulls (0 = no limit)" },
  { "sl stoploss <zenni>", "Stop once down this much, e.g. 500m or 2b (0 = off)" },
  { "sl target <zenni>",   "Stop once up this much (0 = off)" },
  { "sl keep <zenni>",     "Stop before your zenni drops below this (0 = off)" },
  { "sl reset",            "Clear the stats" },
  { "sl help",             "Show this list" },
}

function SL.help()
  cecho("\n<cyan>Slot machine bot (sl) commands:\n")
  for _, row in ipairs(SL.HELP) do cecho(string.format("  <yellow>%-21s<white>%s\n", row[1], row[2])) end
  cecho("  <white>Lucky Tails and STR XP only come from <yellow>[VIP]<white> machines.\n")
end

local function limit(n, isZenni)
  if n == 0 then return "off" end
  return isZenni and fmt(n) or tostring(n)
end

function SL.status()
  local s, n = SL.stats, net()
  cecho("\n<cyan>sl status:\n")
  cecho("  <white>Bot:     " .. (SL.active and "<green>ON" or "<red>OFF") .. "<white>   lines " .. SL.lines ..
    "   delay " .. SL.delay .. "s\n")
  cecho("  <white>Limits:  pulls " .. limit(SL.maxPulls) .. "   stop loss " .. limit(SL.stopLoss, true) ..
    "   target " .. limit(SL.target, true) .. "   keep " .. limit(SL.keep, true) .. "\n")
  cecho(string.format("  <white>Pulls:   %d   winning %d   best win %s\n", s.pulls, s.wins, fmt(s.best)))
  if n then
    cecho("  <white>Zenni:   net " .. (n >= 0 and "<green>" or "<red>") .. signed(n) .. "<white>   now " .. fmt(s.zenni) .. "\n")
  end
  cecho("  <white>Lucky Tails: " .. fmt(s.tails) .. "   STR XP: " .. fmt(s.xp) .. "\n")
end

function SL.command(cmd, arg)
  local n = tonumber(arg)
  if cmd == nil or cmd == "help" then
    SL.help()
  elseif cmd == "start" then
    SL.start()
  elseif cmd == "stop" then
    SL.stop()
  elseif cmd == "status" then
    SL.status()
  elseif cmd == "lines" and n and n >= 1 and n <= 5 then
    SL.lines = math.floor(n)
    info("white", "Playing " .. SL.lines .. " line" .. (SL.lines == 1 and "" or "s") .. " a pull")
  elseif cmd == "delay" and n then
    SL.delay = math.max(1, n)
    info("white", "Delay: " .. SL.delay .. "s")
  elseif cmd == "pulls" and n then
    SL.maxPulls = math.max(0, math.floor(n))
    info("white", "Pull limit: " .. limit(SL.maxPulls))
  elseif (cmd == "stoploss" or cmd == "target" or cmd == "keep") and arg and casino.parseAmount(arg) then
    local field = ({ stoploss = "stopLoss", target = "target", keep = "keep" })[cmd]
    SL[field] = casino.parseAmount(arg)
    info("white", cmd:sub(1, 1):upper() .. cmd:sub(2) .. ": " .. limit(SL[field], true))
  elseif cmd == "reset" then
    SL.stats = newStats()
    info("white", "Stats cleared")
  else
    info("yellow", "Unknown command '" .. tostring(cmd) .. (arg and (" " .. arg) or "") .. "'. Type sl help")
  end
end

casino.register{
  key = "sl", title = "Slots", command = "sl",
  active = function() return SL.active end,
  stop = function() SL.stop() end,
  luckyTails = SL.luckyTails,
  xp = function(n) SL.xpGained(n) end,
  status = function()
    local n = net()
    return string.format("%d pulls, %d winning%s", SL.stats.pulls, SL.stats.wins, n and ("   net " .. signed(n)) or "")
  end,
}
