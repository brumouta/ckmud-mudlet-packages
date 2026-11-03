-- Slot machine bot. Type `sl help` for commands.
--
-- Pulls, waits for the machine's "You won / You lost" line, and pulls again. It reads
-- the reels and scores them with the machine's payout rules, so each win says which
-- lines paid. Slots have no strategy: the only choices are the lines and when to stop.
sl = sl or {}
local SL = sl

-- ---------------------------------------------------------------- settings
SL.lines    = SL.lines or 5      -- lines per pull (1-5); each line is another bet
SL.delay    = SL.delay or 1      -- seconds after a result before the next pull
SL.quiet    = (SL.quiet == nil) and true or SL.quiet   -- one line per pull instead of the reels
SL.maxPulls = SL.maxPulls or 0   -- stop after this many pulls (0 = no limit)
SL.stopLoss = SL.stopLoss or 0   -- stop once down this much zenni (0 = no limit)
SL.target   = SL.target or 0     -- stop once up this much zenni (0 = no limit)
SL.keep     = SL.keep or 0       -- stop before your zenni (MSDP) drops below this
SL.watchdog = 8                  -- seconds without an answer before pulling again
SL.maxRetries = 2                -- unanswered pulls in a row before giving up

-- ---------------------------------------------------------------- state
SL.active = false
SL.state  = "idle"               -- idle | pulling (sent, waiting for the bet) | spinning (waiting for the result)
local function newStats()
  return { pulls = 0, bet = 0, won = 0, wins = 0, best = 0, full = 0, dragonballs = 0, tails = 0, xp = 0, mismatches = 0 }
end
SL.stats = SL.stats or newStats()
local timers = {}

local info = casino.logger("sl")
local num, fmt, signed = casino.num, casino.fmt, casino.signed

-- ---------------------------------------------------------------- reels and payouts
-- From `payout`: multiplier of the line bet for a full line, per lines played
SL.SYMBOLS = {
  X = { mult = 1, name = "Bomb" },        o = { mult = 1.5, name = "Senzu Bean" }, C = { mult = 2, name = "Cherry" },
  B = { mult = 3, name = "Bar" },         BB = { mult = 5, name = "Double Bar" },   BBB = { mult = 8, name = "Triple Bar" },
  Z = { mult = 12, name = "Z" },          ZZ = { mult = 24, name = "Double Z" },    ZZZ = { mult = 36, name = "Triple Z" },
  ["(*)"] = { mult = 250, name = "Dragonball" },
}
-- Lines in the order they are bought: middle, top, bottom, then the two diagonals
SL.LINES = {
  { name = "middle",   cells = { { 2, 1 }, { 2, 2 }, { 2, 3 } } },
  { name = "top",      cells = { { 1, 1 }, { 1, 2 }, { 1, 3 } } },
  { name = "bottom",   cells = { { 3, 1 }, { 3, 2 }, { 3, 3 } } },
  { name = "diagonal", cells = { { 1, 1 }, { 2, 2 }, { 3, 3 } } },
  { name = "diagonal", cells = { { 3, 1 }, { 2, 2 }, { 1, 3 } } },
}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- rows = { {"X","BBB","o"}, {...}, {...} } (top to bottom); perLine = the bet for one line.
-- A full line pays mult * perLine * lines, the first two reels matching pay 10% of that;
-- the middle row and one other row full of the same symbol pay x10, all three rows x25.
function SL.evaluate(rows, lines, perLine)
  local total, hits = 0, {}
  for i = 1, lines do
    local l = SL.LINES[i]
    local a, b, c = rows[l.cells[1][1]][l.cells[1][2]], rows[l.cells[2][1]][l.cells[2][2]], rows[l.cells[3][1]][l.cells[3][2]]
    local sym = SL.SYMBOLS[a]
    if sym and a == b then
      local full = b == c
      total = total + sym.mult * perLine * lines * (full and 1 or 0.1)
      hits[#hits + 1] = { line = l.name, symbol = a, full = full }
    end
  end
  local function rowFull(r) return rows[r][1] == rows[r][2] and rows[r][2] == rows[r][3] end
  if lines >= 3 and rowFull(1) and rowFull(2) and rowFull(3) and rows[1][1] == rows[2][1] and rows[2][1] == rows[3][1] then
    total = total * 25
  elseif lines >= 2 and rowFull(2) and ((rowFull(1) and rows[1][1] == rows[2][1]) or (lines >= 3 and rowFull(3) and rows[3][1] == rows[2][1])) then
    total = total * 10
  end
  return math.floor(total + 0.5), hits
end

local function hitsText(hits)
  local out = {}
  for _, h in ipairs(hits) do
    out[#out + 1] = (h.full and "" or "2x ") .. SL.SYMBOLS[h.symbol].name .. " " .. h.line
  end
  return table.concat(out, ", ")
end

local function rowsText(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = table.concat(r, " ") end
  return table.concat(out, " / ")
end

-- ---------------------------------------------------------------- the loop
local function cancel(name) if timers[name] then killTimer(timers[name]); timers[name] = nil end end
local function later(name, secs, fn)
  cancel(name)
  timers[name] = tempTimer(secs, function() timers[name] = nil; fn() end)
end

local function net() return SL.stats.won - SL.stats.bet end

local function why()
  local s, n = SL.stats, net()
  if SL.maxPulls > 0 and s.pulls >= SL.maxPulls then return "played " .. s.pulls .. " pulls" end
  if SL.stopLoss > 0 and n <= -SL.stopLoss then return "stop loss reached (" .. signed(n) .. ")" end
  if SL.target > 0 and n >= SL.target then return "target reached (" .. signed(n) .. ")" end
  local z = rawget(_G, "MSDP") and MSDP.Player and MSDP.Player.Zenni
  if SL.keep > 0 and type(z) == "number" and z < SL.keep then return "zenni below " .. fmt(SL.keep) end
end

function SL.pull()
  if not SL.active then return end
  local reason = why()
  if reason then return SL.stop(reason) end
  SL.state = "pulling"
  send("pull " .. SL.lines, false)
  later("watchdog", SL.watchdog, function()
    if not SL.active then return end
    if SL.stopping then return SL.stop() end
    SL.retries = (SL.retries or 0) + 1
    if SL.retries > SL.maxRetries then
      return SL.stop("the machine didn't answer " .. SL.retries .. " pulls - not at a slot machine, or out of zenni?")
    end
    SL.pull()
  end)
end

-- "You put 12,500,000 zenni in the slot machine."
function SL.onBet(zenni)
  if not SL.active then return end
  SL.state, SL.retries, SL.rows = "spinning", 0, {}
  SL.gag()
  SL.betZenni = num(zenni)
  SL.stats.pulls = SL.stats.pulls + 1
  SL.stats.bet = SL.stats.bet + SL.betZenni
end

-- "  [  |ZZZ| | X | | C |  ]", three of them, top to bottom
function SL.onReels(a, b, c)
  if not (SL.active and SL.state == "spinning") then return end
  SL.rows[#SL.rows + 1] = { trim(a), trim(b), trim(c) }
  SL.gag()
end

-- "You won 25,000,000 zenni!" / "You lost your 12,500,000 zenni!" (won = "0")
function SL.onResult(won)
  if not (SL.active and SL.state == "spinning") then return end
  SL.gag()
  cancel("watchdog")
  SL.state = "idle"
  local s, paid = SL.stats, num(won)
  s.won = s.won + paid
  local hits = {}
  if SL.rows and #SL.rows == 3 then
    local expect
    expect, hits = SL.evaluate(SL.rows, SL.lines, SL.betZenni / SL.lines)
    if expect ~= paid then
      s.mismatches = s.mismatches + 1
      info("yellow", "Scored " .. fmt(expect) .. " but the machine paid " .. fmt(paid) .. ": " .. rowsText(SL.rows))
    end
  end
  for _, h in ipairs(hits) do
    if h.full then s.full = s.full + 1 end
    if h.full and h.symbol == "(*)" then
      s.dragonballs = s.dragonballs + 1
      info("magenta", "DRAGONBALL LINE! " .. fmt(paid) .. " zenni")
      if alert then alert(10) end
    end
  end
  if paid > 0 then
    s.wins = s.wins + 1
    if paid > s.best then s.best = paid end
  end
  if SL.quiet or paid > 0 then
    local delta = paid - SL.betZenni
    info(paid > SL.betZenni and "green" or paid > 0 and "white" or "grey",
      string.format("%s  %s%s<grey>   pull %d, net %s", SL.rows and #SL.rows == 3 and rowsText(SL.rows) or "",
        paid > 0 and ("won " .. fmt(paid) .. " (" .. signed(delta) .. ")") or "lost",
        #hits > 0 and ("  " .. hitsText(hits)) or "", s.pulls, signed(net())))
  end
  if SL.stopping then return SL.stop() end
  later("next", SL.delay, SL.pull)
end

-- Hide the machine's lines while the bot plays, when quiet: each pull gets one line instead
function SL.gag()
  if SL.active and SL.quiet and SL.state ~= "idle" then deleteLine() end
end

function SL.start()
  if SL.active then return info("yellow", "Already pulling (sl stop to stop)") end
  SL.active, SL.stopping, SL.retries = true, false, 0
  info("green", string.format("Pulling %d line%s. sl stop finishes the pull and stops.", SL.lines, SL.lines == 1 and "" or "s"))
  SL.pull()
end

function SL.stop(reason)
  cancel("watchdog"); cancel("next")
  local was = SL.active
  SL.active, SL.stopping, SL.state = false, false, "idle"
  if reason then info("yellow", "Stopped: " .. reason) elseif was then info("yellow", "Bot OFF") end
  if was then SL.status() end
end

-- Credited by the casino core while the bot plays
function SL.luckyTails(n) SL.stats.tails = SL.stats.tails + n end
function SL.xpGained(n) SL.stats.xp = SL.stats.xp + n end

-- ---------------------------------------------------------------- `sl` alias
SL.HELP = {
  { "sl start",            "Start pulling (stand at a slot machine first)" },
  { "sl stop",             "Finish the pull on the machine, then stop" },
  { "sl status",           "Pulls, zenni in and out, winning pulls, full lines, Lucky Tails, STR XP" },
  { "sl lines <1-5>",      "Lines per pull (default 5); each line costs another bet" },
  { "sl pulls <n>",        "Stop after n pulls (0 = no limit)" },
  { "sl stoploss <zenni>", "Stop once down this much, e.g. 500m or 2b (0 = off)" },
  { "sl target <zenni>",   "Stop once up this much (0 = off)" },
  { "sl keep <zenni>",     "Stop before your zenni drops below this (needs MSDP; 0 = off)" },
  { "sl delay <secs>",     "Seconds between a result and the next pull (default 1)" },
  { "sl quiet on|off",     "One line per pull instead of the reels (default on)" },
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
    "   delay " .. SL.delay .. "s   quiet " .. (SL.quiet and "on" or "off") .. "\n")
  cecho("  <white>Limits:  pulls " .. limit(SL.maxPulls) .. "   stop loss " .. limit(SL.stopLoss, true) ..
    "   target " .. limit(SL.target, true) .. "   keep " .. limit(SL.keep, true) .. "\n")
  local ret = s.bet > 0 and string.format("  (%.1f%% returned)", 100 * s.won / s.bet) or ""
  cecho(string.format("  <white>Pulls:   %d   paying %d   full lines %d   dragonballs %d   best %s\n",
    s.pulls, s.wins, s.full, s.dragonballs, fmt(s.best)))
  cecho("  <white>Zenni:   in " .. fmt(s.bet) .. "   out " .. fmt(s.won) .. "   net " .. (n >= 0 and "<green>" or "<red>") ..
    signed(n) .. "<white>" .. ret .. "\n")
  cecho("  <white>Lucky Tails: " .. fmt(s.tails) .. "   STR XP: " .. fmt(s.xp) .. "\n")
end

function SL.command(cmd, arg)
  local n = tonumber(arg)
  if cmd == nil or cmd == "help" then
    SL.help()
  elseif cmd == "start" then
    SL.start()
  elseif cmd == "stop" then
    if SL.active and SL.state ~= "idle" then
      SL.stopping = true
      info("yellow", "Stopping after this pull")
    else
      SL.stop()
    end
  elseif cmd == "status" then
    SL.status()
  elseif cmd == "lines" and n and n >= 1 and n <= 5 then
    SL.lines = math.floor(n)
    info("white", "Playing " .. SL.lines .. " line" .. (SL.lines == 1 and "" or "s") .. " a pull")
  elseif cmd == "delay" and n then
    SL.delay = math.max(0, n)
    info("white", "Delay: " .. SL.delay .. "s")
  elseif cmd == "pulls" and n then
    SL.maxPulls = math.max(0, math.floor(n))
    info("white", "Pull limit: " .. limit(SL.maxPulls))
  elseif (cmd == "stoploss" or cmd == "target" or cmd == "keep") and arg and casino.parseAmount(arg) then
    local field = ({ stoploss = "stopLoss", target = "target", keep = "keep" })[cmd]
    SL[field] = casino.parseAmount(arg)
    info("white", cmd:sub(1, 1):upper() .. cmd:sub(2) .. ": " .. limit(SL[field], true))
  elseif cmd == "quiet" and (arg == "on" or arg == "off") then
    SL.quiet = arg == "on"
    info("white", "Reels " .. (SL.quiet and "hidden" or "shown") .. " while the bot plays")
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
    local s = SL.stats
    return string.format("%d pulls, %d paying, net %s", s.pulls, s.wins, signed(net()))
  end,
}
