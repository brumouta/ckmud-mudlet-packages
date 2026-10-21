-- Blackjack table bot (basic strategy). Type `bj help` for commands.
bj = bj or {}
local BJ = bj

-- ---------------------------------------------------------------- settings
BJ.betCmd = BJ.betCmd or "blackjack bet"
BJ.delay  = BJ.delay or 1      -- seconds before each action, so the table output settles
BJ.CMD    = { hit = "chit", stand = "cstand", double = "cdouble" }

-- ---------------------------------------------------------------- state
BJ.invited = false   -- dealer offered `cjoin`
BJ.joining = false   -- I typed `cjoin`
BJ.active  = false   -- bot is playing
BJ.me      = nil     -- my name, from the welcome line
BJ.dealer  = {}      -- dealer's visible cards
BJ.hand    = {}      -- my cards
BJ.turnOf  = nil     -- whose turn the dealer says it is
BJ.waiting = false   -- I sent a move and am waiting for the table to change
local function newStats()
  return { rounds = 0, wins = 0, losses = 0, zenniWon = 0, zenniLost = 0, tails = 0, xp = 0,
           hit = 0, stand = 0, double = 0 }
end
BJ.stats   = BJ.stats or newStats()

local function info(color, msg)
  cecho("\n<" .. color .. ">[bj] " .. msg .. "\n")
end

local function later(fn) tempTimer(BJ.delay, fn) end

-- ---------------------------------------------------------------- cards
-- "[ A] [ 4] (15) [STAND]" -> { "A", "4" }   (hidden "[XX]" and tags like "[STAND]" are skipped)
local RANKS = { A = true, J = true, Q = true, K = true }
for n = 2, 10 do RANKS[tostring(n)] = true end

function BJ.parseCards(text)
  local cards = {}
  for rank in text:gmatch("%[%s*(%w+)%s*%]") do
    if RANKS[rank] then cards[#cards + 1] = rank end
  end
  return cards
end

local function value(rank)
  if rank == "A" then return 1 end
  if rank == "J" or rank == "Q" or rank == "K" then return 10 end
  return tonumber(rank) or 0
end

-- Returns total, isSoft (an ace is counting as 11)
function BJ.total(cards)
  local sum, aces = 0, 0
  for _, r in ipairs(cards) do
    sum = sum + value(r)
    if r == "A" then aces = aces + 1 end
  end
  if aces > 0 and sum + 10 <= 21 then return sum + 10, true end
  return sum, false
end

-- ---------------------------------------------------------------- strategy
-- Basic strategy, dealer stands on soft 17. Returns "hit", "stand" or "double".
function BJ.decide(cards, upRank, canDouble)
  local total, soft = BJ.total(cards)
  local up = value(upRank)
  if up == 1 then up = 11 end
  local function dbl(fallback) return canDouble and "double" or fallback end

  if soft then
    if total >= 19 then return "stand" end
    if total == 18 then
      if up >= 3 and up <= 6 then return dbl("stand") end
      if up <= 8 then return "stand" end
      return "hit"
    end
    if total == 17 then return (up >= 3 and up <= 6) and dbl("hit") or "hit" end
    if total >= 15 then return (up >= 4 and up <= 6) and dbl("hit") or "hit" end
    return (up >= 5 and up <= 6) and dbl("hit") or "hit"         -- soft 13-14
  end

  if total >= 17 then return "stand" end
  if total >= 13 then return up <= 6 and "stand" or "hit" end
  if total == 12 then return (up >= 4 and up <= 6) and "stand" or "hit" end
  if total == 11 then return up <= 10 and dbl("hit") or "hit" end
  if total == 10 then return up <= 9 and dbl("hit") or "hit" end
  if total == 9 then return (up >= 3 and up <= 6) and dbl("hit") or "hit" end
  return "hit"
end

-- ---------------------------------------------------------------- table flow
function BJ.invite()
  BJ.invited = true
  if not BJ.active then info("cyan", "Table open - type cjoin to start the bot") end
end

-- `cjoin` alias: only arms the bot when the dealer has offered a seat
function BJ.join()
  BJ.joining = BJ.invited
  send("cjoin", false)
end

function BJ.welcomed(name)
  if not BJ.joining then return end
  local me = rawget(_G, "MSDP") and MSDP.Player.name   -- from the shared MSDP package
  if me and me ~= "" and name:lower() ~= me:lower() then return end  -- someone else joined
  BJ.me, BJ.active, BJ.joining, BJ.invited = name, true, false, false
  info("green", "Joined as " .. name .. ", bot ON (bj stop to quit)")
end

local function isMe(who) return BJ.me ~= nil and who:lower() == BJ.me:lower() end

function BJ.placeBet()
  if not BJ.active then return end
  BJ.dealer, BJ.hand, BJ.turnOf, BJ.waiting = {}, {}, nil, false
  later(function() if BJ.active then send(BJ.betCmd) end end)
end

function BJ.showHand(who, text)
  if not BJ.active then return end
  if who == "Dealer" then
    BJ.dealer = BJ.parseCards(text)
  elseif isMe(who) then
    local cards = BJ.parseCards(text)
    if #cards ~= #BJ.hand then BJ.waiting = false end  -- got a new card: my move went through
    BJ.hand = cards
  end
end

-- "It's Vorrac's turn." / "Current player: Vorrac"
function BJ.turn(who)
  if not BJ.active then return end
  if isMe(who) and not isMe(BJ.turnOf or "") then BJ.waiting = false end
  BJ.turnOf = who
end

-- "Well Vorrac, what would you like to do?" - the dealer is still waiting on me.
-- If my last move was a while ago it must have been lost, so allow the bot to act again.
BJ.NUDGE_AFTER = 5   -- seconds
function BJ.nudge(who)
  if not BJ.active or not isMe(who) then return end
  BJ.turnOf = who
  if os.time() - (BJ.lastMoveAt or 0) >= BJ.NUDGE_AFTER then BJ.waiting = false end
end

-- Options line: "BLACKJACK: Hit(chit), Double Down(cdouble) or Stand(cstand)?"
-- The game repeats it after every prompt, so act only once per table change.
function BJ.options(text)
  if not BJ.active or BJ.waiting or not isMe(BJ.turnOf or "") then return end
  if #BJ.hand == 0 or #BJ.dealer == 0 then
    info("yellow", "Couldn't read the table, play this one by hand")
    BJ.waiting = true
    return
  end
  BJ.waiting = true

  local canDouble = text:find("cdouble", 1, true) ~= nil and #BJ.hand == 2
  local action = BJ.decide(BJ.hand, BJ.dealer[1], canDouble)
  local total, soft = BJ.total(BJ.hand)
  info("white", string.format("%s %d vs %s -> %s", soft and "soft" or "hard", total, BJ.dealer[1], action))

  BJ.stats[action] = BJ.stats[action] + 1
  BJ.lastMoveAt = os.time()
  later(function() if BJ.active then send(BJ.CMD[action]) end end)
end

-- ---------------------------------------------------------------- results
local function num(text) return tonumber((text:gsub(",", ""))) or 0 end

local function fmt(n)
  local str = tostring(math.floor(math.abs(n)))
  str = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. str
end
BJ.fmt = fmt

-- "Let's see who won this round."
function BJ.roundEnd()
  if BJ.active then BJ.stats.rounds = BJ.stats.rounds + 1 end
end

-- "You won 20,000,000 zenni on your main hand!"
function BJ.won(amount)
  if not BJ.active then return end
  BJ.stats.wins = BJ.stats.wins + 1
  BJ.stats.zenniWon = BJ.stats.zenniWon + num(amount)
end

-- "You lost X zenni ..." (wording not confirmed yet)
function BJ.lost(amount)
  if not BJ.active then return end
  BJ.stats.losses = BJ.stats.losses + 1
  BJ.stats.zenniLost = BJ.stats.zenniLost + num(amount)
end

-- "You earn 100 Lucky Tails!"
function BJ.luckyTails(amount)
  if BJ.active then BJ.stats.tails = BJ.stats.tails + num(amount) end
end

-- "You have gained 120,000 intelligence XP."
function BJ.xpGained(amount)
  if BJ.active then BJ.stats.xp = BJ.stats.xp + num(amount) end
end

function BJ.stop()
  BJ.active, BJ.joining, BJ.turnOf, BJ.waiting = false, false, nil, false
  info("yellow", "Bot OFF")
end

-- ---------------------------------------------------------------- `bj` alias
BJ.HELP = {
  { "bj help",          "Show this list" },
  { "bj status",        "Bot state, last hand, wins/losses, zenni, Lucky Tails, XP" },
  { "bj start",         "Turn the bot on without re-joining (if you're already seated)" },
  { "bj stop",          "Turn the bot off (you stay at the table)" },
  { "bj bet <command>", "Change the bet command, e.g. bj bet blackjack bet" },
  { "bj delay <secs>",  "Seconds to wait before each action" },
  { "bj reset",         "Clear the stats" },
}

function BJ.help()
  cecho("\n<cyan>Blackjack bot (bj) commands:\n")
  for _, row in ipairs(BJ.HELP) do
    cecho(string.format("  <yellow>%-20s<white>%s\n", row[1], row[2]))
  end
  cecho("  <white>Join a table by typing <yellow>cjoin<white> when the dealer offers a seat.\n")
end

function BJ.status()
  local s = BJ.stats
  local other = s.rounds - s.wins - s.losses   -- pushes, or losses with unknown wording
  local net = s.zenniWon - s.zenniLost
  cecho("\n<cyan>bj status:\n")
  cecho("  <white>Bot:     " .. (BJ.active and "<green>ON" or "<red>OFF") .. "<white>\n")
  cecho("  <white>Player:  " .. (BJ.me or "-") .. "\n")
  cecho("  <white>Hand:    " .. table.concat(BJ.hand, " ") .. "  vs dealer " .. table.concat(BJ.dealer, " ") .. "\n")
  cecho("  <white>Bet cmd: " .. BJ.betCmd .. "   Delay: " .. BJ.delay .. "s\n")
  cecho(string.format("  <white>Rounds: %d   <green>Won: %d<white>   <red>Lost: %d<white>   Other: %d\n",
    s.rounds, s.wins, s.losses, other))
  cecho("  <white>Zenni:   <green>+" .. fmt(s.zenniWon) .. "<white>  <red>-" .. fmt(s.zenniLost) ..
    "<white>  net " .. (net >= 0 and "<green>+" or "<red>") .. fmt(net) .. "<white>\n")
  cecho("  <white>Lucky Tails: " .. fmt(s.tails) .. "   Intelligence XP: " .. fmt(s.xp) .. "\n")
  cecho(string.format("  <white>Moves:   hit %d   stand %d   double %d\n", s.hit, s.stand, s.double))
end

function BJ.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    BJ.help()
  elseif cmd == "status" then
    BJ.status()
  elseif cmd == "start" then
    BJ.me = BJ.me or (rawget(_G, "MSDP") and MSDP.Player.name)
    if not BJ.me then return info("yellow", "Don't know your name yet - join with cjoin instead") end
    BJ.active = true
    info("green", "Bot ON as " .. BJ.me)
  elseif cmd == "stop" then
    BJ.stop()
  elseif cmd == "bet" and arg then
    BJ.betCmd = arg
    info("white", "Bet command set to '" .. arg .. "'")
  elseif cmd == "delay" and tonumber(arg) then
    BJ.delay = tonumber(arg)
    info("white", "Delay set to " .. BJ.delay .. "s")
  elseif cmd == "reset" then
    BJ.stats = newStats()
    info("white", "Stats cleared")
  else
    info("yellow", "Unknown command '" .. tostring(cmd) .. "'. Type bj help")
  end
end
