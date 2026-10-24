-- Video poker bot (Jacks or Better). Type `vp help` for commands.
--
-- Deals with `vpoker deal`, holds the cards the standard Jacks or Better strategy
-- keeps, draws with `vpoker draw <positions>` and deals again. It scores the final
-- hand itself and reads the real zenni from the machine's Credit line.
vp = vp or {}
local VP = vp

-- ---------------------------------------------------------------- settings
VP.coins    = VP.coins or 5      -- coins per hand; only 5 pays the 4,000 coin royal
VP.delay    = VP.delay or 1      -- seconds before each command, so the output settles
VP.quiet    = (VP.quiet == nil) and true or VP.quiet   -- hide the paytable while the bot plays
VP.maxHands = VP.maxHands or 0   -- stop after this many hands (0 = no limit)
VP.stopLoss = VP.stopLoss or 0   -- stop once down this much zenni (0 = no limit)
VP.target   = VP.target or 0     -- stop once up this much zenni (0 = no limit)
VP.watchdog = 10                 -- seconds without an answer before looking at the machine
VP.maxRetries = 3                -- unanswered looks in a row before giving up

-- ---------------------------------------------------------------- state
VP.active   = false
VP.stopping = false              -- finish the hand on the table, then stop
VP.state    = "idle"             -- idle | looking | dealing | drawing
VP.cards    = nil                -- the last five cards shown
local function newStats()
  return { hands = 0, coinsBet = 0, coinsWon = 0, byHand = {}, tails = 0, xp = 0,
           startCredit = nil, credit = nil, best = nil }
end
VP.stats = VP.stats or newStats()

local function info(color, msg) cecho("\n<" .. color .. ">[vp] " .. msg .. "\n") end

local function num(text) return tonumber((tostring(text):gsub(",", ""))) or 0 end

local function fmt(n)
  local str = tostring(math.floor(math.abs(n)))
  str = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. str
end
VP.fmt = fmt

local function signed(n) return (n >= 0 and "+" or "") .. fmt(n) end

-- "500m", "1.5b", "250k", "25,000,000" -> zenni
function VP.parseAmount(text)
  local n, unit = tostring(text):lower():gsub(",", ""):match("^%s*(%d*%.?%d+)%s*([kmb]?)%s*$")
  if not n then return nil end
  local mult = ({ k = 1e3, m = 1e6, b = 1e9 })[unit] or 1
  return math.floor(tonumber(n) * mult + 0.5)
end

-- ---------------------------------------------------------------- cards
local RANK = { T = 10, J = 11, Q = 12, K = 13, A = 14 }
local FACE = { [10] = "10", [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }

-- "  [3C]      [JC]      [QS]      [10D]     [KH]" -> { {r=3, s="C", pos=1, text="3C"}, ... }
function VP.parseCards(text)
  local cards = {}
  for r, s in text:gmatch("%[%s*([%dTJQKA]+)([CDHS])%s*%]") do
    local rank = RANK[r] or tonumber(r)
    if rank and rank >= 2 and rank <= 14 then
      cards[#cards + 1] = { r = rank, s = s, pos = #cards + 1, text = (FACE[rank] or r) .. s }
    end
  end
  return cards
end

local function cardsText(cards, positions)
  local out = {}
  if positions then
    for _, p in ipairs(positions) do out[#out + 1] = cards[p].text end
  else
    for _, c in ipairs(cards) do out[#out + 1] = c.text end
  end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------- scoring
VP.HANDS = {   -- best first; pay = coins per coin bet
  { key = "royal",     name = "Royal Flush",     pay = 250 },
  { key = "sflush",    name = "Straight Flush",  pay = 50 },
  { key = "quads",     name = "Four of a Kind",  pay = 25 },
  { key = "fullhouse", name = "Full House",      pay = 8 },
  { key = "flush",     name = "Flush",           pay = 5 },
  { key = "straight",  name = "Straight",        pay = 4 },
  { key = "trips",     name = "Three of a Kind", pay = 3 },
  { key = "twopair",   name = "Two Pair",        pay = 2 },
  { key = "jacks",     name = "Jacks or Better", pay = 1 },
  { key = "nothing",   name = "Nothing",         pay = 0 },
}
local HAND = {}
for i, h in ipairs(VP.HANDS) do h.order = i; HAND[h.key] = h end
VP.HAND = HAND

-- Coins paid for a hand at a bet of `coins` (the royal jumps to 4,000 at five coins)
function VP.payout(key, coins)
  if key == "royal" and coins == 5 then return 4000 end
  return HAND[key].pay * coins
end

local function rankCounts(cards)
  local counts = {}
  for _, c in ipairs(cards) do counts[c.r] = (counts[c.r] or 0) + 1 end
  return counts
end

-- Ranks fit inside five in a row (ace high or low), all different
local function fitsStraight(ranks)
  local seen = {}
  for _, r in ipairs(ranks) do
    if seen[r] then return false end
    seen[r] = true
  end
  local function span(aceLow)
    local lo, hi = 99, 0
    for _, r in ipairs(ranks) do
      if aceLow and r == 14 then r = 1 end
      lo, hi = math.min(lo, r), math.max(hi, r)
    end
    return hi - lo + 1
  end
  return span(false) <= 5 or (seen[14] and span(true) <= 5) or false
end

-- The five-card hand: one of the VP.HANDS keys
function VP.score(cards)
  local ranks, flush = {}, true
  for i, c in ipairs(cards) do
    ranks[i] = c.r
    if c.s ~= cards[1].s then flush = false end
  end
  local straight = fitsStraight(ranks)
  local low = 99
  for _, r in ipairs(ranks) do low = math.min(low, r) end
  if straight and flush then return low == 10 and "royal" or "sflush" end
  local pairs_, trips, quads, highPair = 0, false, false, false
  for r, n in pairs(rankCounts(cards)) do
    if n == 4 then quads = true end
    if n == 3 then trips = true end
    if n == 2 then pairs_ = pairs_ + 1; if r >= 11 then highPair = true end end
  end
  if quads then return "quads" end
  if trips and pairs_ == 1 then return "fullhouse" end
  if flush then return "flush" end
  if straight then return "straight" end
  if trips then return "trips" end
  if pairs_ == 2 then return "twopair" end
  if highPair then return "jacks" end
  return "nothing"
end

-- ---------------------------------------------------------------- strategy
-- Jacks or Better 8/5 (this machine: Full House 8, Flush 5), the usual ranked list:
-- hold the first pattern from the top that the hand has.
local function isHigh(c) return c.r >= 11 end

-- Every way to pick k of the 5 positions, in order
local function subsets(k)
  local out = {}
  local function walk(start, picked)
    if #picked == k then out[#out + 1] = { (table.unpack or unpack)(picked) }; return end
    for i = start, 5 do
      picked[#picked + 1] = i
      walk(i + 1, picked)
      picked[#picked] = nil
    end
  end
  walk(1, {})
  return out
end
local SUBSETS = { [2] = subsets(2), [3] = subsets(3), [4] = subsets(4) }

local function ranksAt(cards, set)
  local ranks = {}
  for i, p in ipairs(set) do ranks[i] = cards[p].r end
  return ranks
end

local function suitedSet(cards, set)
  for _, p in ipairs(set) do
    if cards[p].s ~= cards[set[1]].s then return false end
  end
  return true
end

local function highsIn(cards, set)
  local n = 0
  for _, p in ipairs(set) do if isHigh(cards[p]) then n = n + 1 end end
  return n
end

-- Positions of the cards matching pred
local function where(cards, pred)
  local out = {}
  for i, c in ipairs(cards) do if pred(c) then out[#out + 1] = i end end
  return out
end

-- The first k-card subset that passes test
local function firstSubset(cards, k, test)
  for _, set in ipairs(SUBSETS[k]) do
    if test(set) then return set end
  end
end

local function suitedRanks(cards, wanted)
  for _, suit in ipairs({ "C", "D", "H", "S" }) do
    local s = {}
    for _, r in ipairs(wanted) do
      for i, c in ipairs(cards) do if c.r == r and c.s == suit then s[#s + 1] = i; break end end
    end
    if #s == #wanted then table.sort(s); return s end
  end
end

local function anyRanks(cards, wanted)
  local s = {}
  for _, r in ipairs(wanted) do
    for i, c in ipairs(cards) do if c.r == r then s[#s + 1] = i; break end end
  end
  if #s == #wanted then table.sort(s); return s end
end

-- Three to a straight flush, by type (1 best): needs 3 suited cards inside five in a row.
-- Type 1: high cards >= gaps. Type 2: one gap and no high card, two gaps and one high card,
-- ace-low (A23, A45...) or 234. Type 3: two gaps and no high card.
local function sf3Type(cards, set)
  if not suitedSet(cards, set) then return nil end
  local ranks = ranksAt(cards, set)
  if not fitsStraight(ranks) then return nil end
  local lo, hi, hasAce = 99, 0, false
  for _, r in ipairs(ranks) do
    if r == 14 then hasAce = true end
    lo, hi = math.min(lo, r), math.max(hi, r)
  end
  if hasAce and lo <= 5 then return 2 end                      -- ace low
  if lo == 2 and hi == 4 then return 2 end                     -- 234
  local gaps, highs = (hi - lo + 1) - 3, highsIn(cards, set)
  if highs >= gaps then return 1 end
  if (gaps == 1 and highs == 0) or (gaps == 2 and highs == 1) then return 2 end
  return 3
end

local function sf3(cards, wantType)
  return firstSubset(cards, 3, function(set) return sf3Type(cards, set) == wantType end)
end

-- Four cards: outside = four in a row that can complete at either end (2345 .. 10JQK)
local function outside4(cards, set)
  local ranks = ranksAt(cards, set)
  if not fitsStraight(ranks) then return false end
  local lo, hi = 99, 0
  for _, r in ipairs(ranks) do lo, hi = math.min(lo, r), math.max(hi, r) end
  return hi - lo == 3 and lo >= 2 and hi <= 13
end

VP.STRATEGY = {
  { "pat royal, straight flush or quads", function(c)
      local k = VP.score(c)
      if k == "royal" or k == "sflush" or k == "quads" then return { 1, 2, 3, 4, 5 } end
    end },
  { "4 to a royal flush", function(c)
      for _, suit in ipairs({ "C", "D", "H", "S" }) do
        local set = where(c, function(x) return x.s == suit and x.r >= 10 end)
        if #set == 4 then return set end
      end
    end },
  { "pat full house, flush or straight", function(c)
      local k = VP.score(c)
      if k == "fullhouse" or k == "flush" or k == "straight" then return { 1, 2, 3, 4, 5 } end
    end },
  { "three of a kind", function(c)
      local counts = rankCounts(c)
      local set = where(c, function(x) return counts[x.r] == 3 end)
      if #set == 3 then return set end
    end },
  { "4 to a straight flush", function(c)
      return firstSubset(c, 4, function(set) return suitedSet(c, set) and fitsStraight(ranksAt(c, set)) end)
    end },
  { "two pair", function(c)
      local counts = rankCounts(c)
      local set = where(c, function(x) return counts[x.r] == 2 end)
      if #set == 4 then return set end
    end },
  { "high pair", function(c)
      local counts = rankCounts(c)
      local set = where(c, function(x) return counts[x.r] == 2 and x.r >= 11 end)
      if #set == 2 then return set end
    end },
  { "3 to a royal flush", function(c)
      for _, suit in ipairs({ "C", "D", "H", "S" }) do
        local set = where(c, function(x) return x.s == suit and x.r >= 10 end)
        if #set == 3 then return set end
      end
    end },
  { "4 to a flush", function(c)
      for _, suit in ipairs({ "C", "D", "H", "S" }) do
        local set = where(c, function(x) return x.s == suit end)
        if #set == 4 then return set end
      end
    end },
  { "10-J-Q-K", function(c) return anyRanks(c, { 10, 11, 12, 13 }) end },
  { "low pair", function(c)
      local counts = rankCounts(c)
      local set = where(c, function(x) return counts[x.r] == 2 end)
      if #set == 2 then return set end
    end },
  { "4 to an outside straight", function(c)
      return firstSubset(c, 4, function(set) return outside4(c, set) end)
    end },
  { "3 to a straight flush", function(c) return sf3(c, 1) end },
  { "suited Q-J", function(c) return suitedRanks(c, { 11, 12 }) end },
  { "J-Q-K-A", function(c) return anyRanks(c, { 11, 12, 13, 14 }) end },
  { "suited K-Q or K-J", function(c) return suitedRanks(c, { 12, 13 }) or suitedRanks(c, { 11, 13 }) end },
  { "suited A-K, A-Q or A-J", function(c)
      return suitedRanks(c, { 13, 14 }) or suitedRanks(c, { 12, 14 }) or suitedRanks(c, { 11, 14 })
    end },
  { "4 to an inside straight with 3 high cards", function(c)
      return firstSubset(c, 4, function(set)
        return fitsStraight(ranksAt(c, set)) and not outside4(c, set) and highsIn(c, set) == 3
      end)
    end },
  { "3 to a straight flush (weaker)", function(c) return sf3(c, 2) end },
  { "J-Q-K", function(c) return anyRanks(c, { 11, 12, 13 }) end },
  { "J-Q", function(c) return anyRanks(c, { 11, 12 }) end },
  { "suited 10-J", function(c) return suitedRanks(c, { 10, 11 }) end },
  { "2 high cards", function(c)
      local highs = where(c, isHigh)
      if #highs < 2 then return nil end
      table.sort(highs, function(a, b) return c[a].r < c[b].r end)  -- the two lowest
      local set = { highs[1], highs[2] }
      table.sort(set)
      return set
    end },
  { "suited 10-Q", function(c) return suitedRanks(c, { 10, 12 }) end },
  { "suited 10-K", function(c) return suitedRanks(c, { 10, 13 }) end },
  { "one high card", function(c)
      local set = where(c, isHigh)
      if #set == 1 then return set end
    end },
  { "3 to a straight flush (weakest)", function(c) return sf3(c, 3) end },
}

-- Which positions to hold, and why. Discards everything when nothing on the list fits.
function VP.decide(cards)
  for _, rule in ipairs(VP.STRATEGY) do
    local set = rule[2](cards)
    if set then return set, rule[1] end
  end
  return {}, "nothing worth keeping"
end

-- ---------------------------------------------------------------- the machine
local function cancel(name)
  if VP[name] then killTimer(VP[name]); VP[name] = nil end
end

local function later(name, secs, fn)
  cancel(name)
  VP[name] = tempTimer(secs, function() VP[name] = nil; fn() end)
end

-- If the machine doesn't answer (lag, a lost command), look at it: `vpoker` shows
-- the cards on the table and the credit, and the bot carries on from there.
local function armWatchdog()
  later("_watchdog", VP.watchdog, function()
    if not VP.active or VP.state == "idle" then return end
    VP.retries = (VP.retries or 0) + 1
    if VP.retries > VP.maxRetries then
      VP.stop("the machine stopped answering. Are you at the video poker machine?")
      return
    end
    VP.look()
  end)
end

local function command(cmd)
  send(cmd, false)
  armWatchdog()
end

function VP.look()
  VP.state = "looking"
  command("vpoker")
end

-- The reason to stop, if a limit was reached
function VP.limitReached()
  local s = VP.stats
  local net = (s.credit and s.startCredit) and (s.credit - s.startCredit) or 0
  if VP.maxHands > 0 and s.hands >= VP.maxHands then return "played " .. s.hands .. " hands" end
  if VP.stopLoss > 0 and net <= -VP.stopLoss then return "down " .. fmt(-net) .. " zenni (stop loss)" end
  if VP.target > 0 and net >= VP.target then return "up " .. fmt(net) .. " zenni (target reached)" end
  if s.credit and VP.betZenni and s.credit < VP.betZenni then return "not enough credit for another hand" end
end

function VP.deal()
  if not VP.active then return end
  if VP.stopping then return VP.stop() end
  local why = VP.limitReached()
  if why then return VP.stop(why) end
  VP.state = "dealing"
  command(VP.coins == 5 and "vpoker deal" or ("vpoker deal " .. VP.coins))
end

-- "You feed 25,000,000 zenni into the machine for 5 coins."
function VP.onFeed(zenni, coins)
  VP.betZenni = num(zenni)
  VP.betCoins = tonumber(coins)
end

-- The five cards line
function VP.onCards(text)
  local cards = VP.parseCards(text)
  if #cards == 5 then VP.cards = cards end
end

-- "Type 'vpoker hold <positions>' to keep cards, then 'vpoker draw'.": a hand waits for us
function VP.onHoldPrompt()
  if not VP.active then return end
  cancel("_next")                      -- looking found a hand on the table: play it, don't deal
  if not VP.cards then return VP.stop("couldn't read the cards, play this hand by hand") end
  local hold, why = VP.decide(VP.cards)
  VP.retries = 0
  VP.state = "drawing"
  VP.lastHold = { cards = VP.cards, hold = hold, why = why }
  local kept = #hold > 0 and cardsText(VP.cards, hold) or "nothing"
  info("white", cardsText(VP.cards) .. "  <grey>->  <white>hold " .. kept .. " <grey>(" .. why .. ")")
  later("_act", VP.delay, function()
    if not VP.active then return end
    if #hold == 0 then
      send("vpoker hold none", false)
      command("vpoker draw")
    else
      command("vpoker draw " .. table.concat(hold))
    end
  end)
end

-- "  Credit: 261,426,214,676 zenni   Bet: 5 coins (25,000,000 zenni)"
function VP.onCredit(credit, text)
  local s = VP.stats
  s.credit = num(credit)
  local coins, zenni = (text or ""):match("Bet:%s*(%d+)%s*coins?%s*%(([%d,]+)")
  if zenni then VP.betCoins, VP.betZenni = tonumber(coins), num(zenni) end
  if not VP.active then return end
  if not s.startCredit then
    -- a dealing screen shows the credit after the bet was paid
    s.startCredit = s.credit + ((VP.state == "dealing" and VP.betZenni) or 0)
  end
  if VP.state == "drawing" then
    cancel("_watchdog")
    VP.state = "settling"
    later("_next", VP.delay, function() VP.handDone(); VP.deal() end)   -- cards may follow the credit line
  elseif VP.state == "looking" then
    cancel("_watchdog")
    later("_next", VP.delay + 0.5, VP.deal)       -- unless a hold prompt says a hand is waiting
  end
end

-- Score the drawn hand and count it
function VP.handDone()
  local s, cards = VP.stats, VP.cards
  local coins = VP.betCoins or VP.coins
  s.hands = s.hands + 1
  s.coinsBet = s.coinsBet + coins
  if not cards then return end
  local key = VP.score(cards)
  local won = VP.payout(key, coins)
  s.coinsWon = s.coinsWon + won
  s.byHand[key] = (s.byHand[key] or 0) + 1
  if key ~= "nothing" and (not s.best or HAND[key].order < HAND[s.best].order) then s.best = key end
  local net = (s.credit and s.startCredit) and (s.credit - s.startCredit) or 0
  local color = won > coins and "green" or won == coins and "white" or "grey"
  info(color, string.format("%s  %s%s<grey>   hand %d, net %s zenni", cardsText(cards), HAND[key].name,
    won > 0 and (" +" .. won .. " coins") or "", s.hands, signed(net)))
  if key == "royal" then
    info("magenta", "ROYAL FLUSH! " .. fmt(won) .. " coins")
    if alert then alert(10) end
  end
end

-- "You earn 100 Lucky Tails!" / "You have gained 120,000 strength XP."
function VP.luckyTails(amount) if VP.active then VP.stats.tails = VP.stats.tails + num(amount) end end
function VP.xpGained(amount) if VP.active then VP.stats.xp = VP.stats.xp + num(amount) end end

-- Hide the paytable that comes with every deal and draw (only while the bot plays)
function VP.gag()
  if VP.active and VP.quiet and VP.state ~= "idle" then deleteLine() end
end

function VP.start()
  if VP.active then return info("yellow", "Already playing (vp stop to stop)") end
  VP.active, VP.stopping, VP.retries = true, false, 0
  VP.stats.startCredit = nil
  info("green", string.format("Bot ON: %d coin%s a hand. vp stop finishes the hand and stops.",
    VP.coins, VP.coins == 1 and "" or "s"))
  VP.look()
end

function VP.stop(why)
  for _, t in ipairs({ "_watchdog", "_next", "_act" }) do cancel(t) end
  local wasActive = VP.active
  VP.active, VP.stopping, VP.state = false, false, "idle"
  if why then info("yellow", "Stopped: " .. why) elseif wasActive then info("yellow", "Bot OFF") end
  if wasActive then VP.status() end
end

-- ---------------------------------------------------------------- `vp` alias
VP.HELP = {
  { "vp start",            "Start playing (sit at the machine first)" },
  { "vp stop",             "Finish the hand on the table, then stop" },
  { "vp stop now",         "Stop right away (a dealt hand stays on the machine)" },
  { "vp status",           "Hands, results, coins and zenni won or lost, Lucky Tails, XP" },
  { "vp advise",           "What the strategy holds for the cards on screen, without playing" },
  { "vp coins <1-5>",      "Coins a hand (default 5, the only bet that pays the 4,000 coin royal)" },
  { "vp hands <n>",        "Stop after n hands (0 = no limit)" },
  { "vp stoploss <zenni>", "Stop once down this much, e.g. 500m or 2b (0 = off)" },
  { "vp target <zenni>",   "Stop once up this much (0 = off)" },
  { "vp delay <secs>",     "Seconds before each command (default 1)" },
  { "vp quiet on|off",     "Hide the paytable while the bot plays (default on)" },
  { "vp reset",            "Clear the stats" },
  { "vp help",             "Show this list" },
}

function VP.help()
  cecho("\n<cyan>Video poker bot (vp) commands:\n")
  for _, row in ipairs(VP.HELP) do cecho(string.format("  <yellow>%-21s<white>%s\n", row[1], row[2])) end
end

local function limitText(n, zenni)
  if n == 0 then return "off" end
  return zenni and fmt(n) or tostring(n)
end

function VP.status()
  local s = VP.stats
  cecho("\n<cyan>vp status:\n")
  cecho("  <white>Bot:      " .. (VP.active and "<green>ON" or "<red>OFF") .. "<white>   coins " .. VP.coins ..
    "   delay " .. VP.delay .. "s   quiet " .. (VP.quiet and "on" or "off") .. "\n")
  cecho("  <white>Limits:   hands " .. limitText(VP.maxHands) .. "   stop loss " .. limitText(VP.stopLoss, true) ..
    "   target " .. limitText(VP.target, true) .. "\n")
  local ret = s.coinsBet > 0 and string.format("  (%.1f%% returned)", 100 * s.coinsWon / s.coinsBet) or ""
  cecho(string.format("  <white>Hands:    %d   coins bet %s, won %s%s\n", s.hands, fmt(s.coinsBet), fmt(s.coinsWon), ret))
  for _, h in ipairs(VP.HANDS) do
    local n = s.byHand[h.key]
    if n then cecho(string.format("  <white>  %-16s %d\n", h.name, n)) end
  end
  if s.credit and s.startCredit then
    local net = s.credit - s.startCredit
    cecho("  <white>Zenni:    net " .. (net >= 0 and "<green>" or "<red>") .. signed(net) ..
      "<white>   credit " .. fmt(s.credit) .. "\n")
  end
  cecho("  <white>Lucky Tails: " .. fmt(s.tails) .. "   STR XP: " .. fmt(s.xp) ..
    (s.best and ("   best hand: " .. HAND[s.best].name) or "") .. "\n")
end

function VP.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    VP.help()
  elseif cmd == "start" then
    VP.start()
  elseif cmd == "stop" then
    if arg == "now" or not VP.active or VP.state == "looking" then
      VP.stop()
    else
      VP.stopping = true
      info("yellow", "Stopping after this hand")
    end
  elseif cmd == "status" then
    VP.status()
  elseif cmd == "advise" then
    if not VP.cards then return info("yellow", "No cards seen yet - type vpoker") end
    local hold, why = VP.decide(VP.cards)
    info("white", cardsText(VP.cards) .. "  ->  " ..
      (#hold > 0 and ("vpoker draw " .. table.concat(hold) .. "  (hold " .. cardsText(VP.cards, hold) .. ", " .. why .. ")")
        or ("vpoker hold none, then vpoker draw  (" .. why .. ")")))
  elseif cmd == "coins" and tonumber(arg) and tonumber(arg) >= 1 and tonumber(arg) <= 5 then
    VP.coins = math.floor(tonumber(arg))
    info("white", "Betting " .. VP.coins .. " coin" .. (VP.coins == 1 and "" or "s") .. " a hand" ..
      (VP.coins < 5 and " (the royal pays 4,000 coins only at 5)" or ""))
  elseif cmd == "hands" and tonumber(arg) then
    VP.maxHands = math.max(0, math.floor(tonumber(arg)))
    info("white", "Hand limit: " .. limitText(VP.maxHands))
  elseif (cmd == "stoploss" or cmd == "target") and arg and VP.parseAmount(arg) then
    local field = cmd == "stoploss" and "stopLoss" or "target"
    VP[field] = VP.parseAmount(arg)
    info("white", (cmd == "stoploss" and "Stop loss: " or "Target: ") .. limitText(VP[field], true))
  elseif cmd == "delay" and tonumber(arg) then
    VP.delay = math.max(0, tonumber(arg))
    info("white", "Delay: " .. VP.delay .. "s")
  elseif cmd == "quiet" and (arg == "on" or arg == "off") then
    VP.quiet = arg == "on"
    info("white", "Paytable " .. (VP.quiet and "hidden" or "shown") .. " while the bot plays")
  elseif cmd == "reset" then
    VP.stats = newStats()
    info("white", "Stats cleared")
  else
    info("yellow", "Unknown command '" .. tostring(cmd) .. (arg and (" " .. arg) or "") .. "'. Type vp help")
  end
end
