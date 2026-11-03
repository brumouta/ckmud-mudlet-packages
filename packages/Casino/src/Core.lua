-- Lucky Monkey Casino: what every game shares. Type `casino` for the games and their commands.
--
-- Each game is its own script with its own command (bj, vp, hs...) and registers here with
-- casino.register. The core owns what the casino does the same way at every table: the
-- `cjoin` seat, Lucky Tails and stat XP from wins, and number/zenni formatting.
casino = casino or {}
local C = casino

C.games = C.games or {}       -- registered games, in load order
local function newStats() return { tails = 0, xp = {} } end
C.stats = C.stats or newStats()

-- ---------------------------------------------------------------- helpers
-- A `[tag] message` line, e.g. casino.logger("bj")("green", "Bot ON")
function C.logger(tag)
  return function(color, msg) cecho("\n<" .. color .. ">[" .. tag .. "] " .. msg .. "\n") end
end
local info = C.logger("casino")

-- "25,000,000" -> 25000000
function C.num(text) return tonumber((tostring(text):gsub(",", ""))) or 0 end

-- 25000000 -> "25,000,000"
function C.fmt(n)
  local str = tostring(math.floor(math.abs(n)))
  str = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. str
end

function C.signed(n) return (n >= 0 and "+" or "") .. C.fmt(n) end

-- "500m", "1.5b", "250k", "25,000,000" -> zenni
function C.parseAmount(text)
  local n, unit = tostring(text):lower():gsub(",", ""):match("^%s*(%d*%.?%d+)%s*([kmb]?)%s*$")
  if not n then return nil end
  local mult = ({ k = 1e3, m = 1e6, b = 1e9 })[unit] or 1
  return math.floor(tonumber(n) * mult + 0.5)
end

-- My name, from the shared MSDP package
function C.me()
  local name = rawget(_G, "MSDP") and MSDP.Player and MSDP.Player.name
  if name and name ~= "" then return name end
end

-- ---------------------------------------------------------------- games
-- casino.register{
--   key = "bj", title = "Blackjack", command = "bj",
--   active = function() ... end,    -- is the bot playing right now
--   stop = function() ... end,      -- `casino stop`
--   status = function() ... end,    -- one line for `casino status`
--   join = function() ... end,      -- you typed `cjoin` (table games)
--   luckyTails = function(n) ... end, xp = function(n, stat) ... end,
-- }
function C.register(game)
  for i, g in ipairs(C.games) do
    if g.key == game.key then C.games[i] = game; return game end   -- reloaded script
  end
  C.games[#C.games + 1] = game
  return game
end

local function playing()
  for _, g in ipairs(C.games) do
    if g.active and g.active() then return g end
  end
end

-- ---------------------------------------------------------------- shared lines
-- `cjoin` alias: every table game seats you with it, so each game decides if it was its table
function C.join()
  for _, g in ipairs(C.games) do
    if g.join then g.join() end
  end
  send("cjoin", false)
end

-- Rewards only count while a bot is playing: the same lines show up outside the casino too.
-- "You earn 100 Lucky Tails!"
function C.luckyTails(amount)
  local g = playing()
  if not g then return end
  local n = C.num(amount)
  C.stats.tails = C.stats.tails + n
  if g.luckyTails then g.luckyTails(n) end
end

-- "You have gained 120,000 intelligence XP." / "... strength XP." / "... STR XP."
function C.xpGained(amount, stat)
  local g = playing()
  if not g then return end
  local n = C.num(amount)
  stat = stat:lower()
  C.stats.xp[stat] = (C.stats.xp[stat] or 0) + n
  if g.xp then g.xp(n, stat) end
end

-- ---------------------------------------------------------------- `casino` alias
function C.help()
  cecho("\n<cyan>Lucky Monkey Casino:\n")
  for _, g in ipairs(C.games) do
    cecho(string.format("  <yellow>%-10s<white>%s  <grey>(%s help)\n", g.command, g.title, g.command))
  end
  cecho("  <yellow>casino status<white>  every game at a glance, Lucky Tails and XP this session\n")
  cecho("  <yellow>casino stop<white>    stop every bot\n")
  cecho("  <yellow>casino reset<white>   clear the casino-wide Lucky Tails and XP\n")
end

function C.status()
  cecho("\n<cyan>casino status:\n")
  for _, g in ipairs(C.games) do
    local on = g.active and g.active()
    cecho(string.format("  <white>%-12s %s<white>  %s\n", g.title, on and "<green>ON " or "<grey>off",
      g.status and g.status() or ""))
  end
  local xp = {}
  for stat, n in pairs(C.stats.xp) do xp[#xp + 1] = C.fmt(n) .. " " .. stat end
  table.sort(xp)
  cecho("  <white>Lucky Tails: " .. C.fmt(C.stats.tails) .. "   XP: " .. (#xp > 0 and table.concat(xp, ", ") or "0") .. "\n")
end

function C.command(cmd)
  if cmd == nil or cmd == "help" then
    C.help()
  elseif cmd == "status" then
    C.status()
  elseif cmd == "stop" then
    for _, g in ipairs(C.games) do
      if g.stop and g.active and g.active() then g.stop() end
    end
    info("yellow", "Every bot stopped")
  elseif cmd == "reset" then
    C.stats = newStats()
    info("white", "Casino-wide stats cleared")
  else
    info("yellow", "Unknown command '" .. tostring(cmd) .. "'. Type casino help")
  end
end
