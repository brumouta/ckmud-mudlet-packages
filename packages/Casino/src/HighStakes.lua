-- High Stakes tournament advisor (no limit Texas Hold'em). Type `hs help` for commands.
--
-- On your turn it shows your hand, your chance to win against the players still in,
-- the pot odds and a tight-aggressive suggestion. `hs go` sends the suggestion; if the
-- dealer warns "ten seconds" before you've moved, it sends it for you (`hs auto off` to stop that).
hs = hs or {}
local HS = hs

-- ---------------------------------------------------------------- settings
HS.enabled = (HS.enabled == nil) and true or HS.enabled   -- show advice on your turn
HS.autoGo  = (HS.autoGo == nil) and true or HS.autoGo    -- play the suggestion at the ten seconds warning
HS.sims    = HS.sims or 3000      -- simulated deals per decision (more = steadier %, slower)

-- ---------------------------------------------------------------- state
local function newHand()
  return { hole = nil, board = {}, folded = {}, allin = {}, turn = nil, aggr = {}, called = {}, raised = {}, shoved = {} }
end
HS.hand    = HS.hand or newHand()
HS.seats   = HS.seats or {}       -- players with chips, from the table display
HS.stacks  = HS.stacks or {}      -- exact stacks from the table display
HS.bb      = HS.bb or 100000000   -- big blind
HS.early   = HS.early or false    -- first 10 hands: fixed bets, no all in
HS.players = HS.players or {}     -- name -> { allins = n, shows = { "6H 9D: Two Pair", ... } }
local function newStats() return { hands = 0, won = 0, wonZenni = 0 } end
HS.stats   = HS.stats or newStats()

local info = casino.logger("hs")
local num = casino.num

-- "1.1B", "225M", "9.6B", "900K" -> zenni
function HS.short(text)
  local n, unit = tostring(text):upper():match("^([%d%.]+)([KMB]?)$")
  if not n then return nil end
  return math.floor(tonumber(n) * (({ K = 1e3, M = 1e6, B = 1e9 })[unit] or 1) + 0.5)
end

-- 1125000000 -> "1.13B" for display
local function brief(n)
  if n >= 1e9 then return (string.format("%.2f", n / 1e9):gsub("%.?0+$", "")) .. "B" end
  if n >= 1e6 then return (string.format("%.1f", n / 1e6):gsub("%.?0+$", "")) .. "M" end
  return tostring(math.floor(n))
end
HS.brief = brief

-- An amount for cbet/craise: "300m", "2.5b"
function HS.amount(n)
  local m = math.ceil(n / 1e6 - 1e-9)
  if m >= 1000 and m % 100 == 0 then return (string.format("%.1f", m / 1000):gsub("%.0$", "")) .. "b" end
  return m .. "m"
end

local function me()
  local name = HS.me or casino.me()
  if name and name ~= "" then return name end
end

local function isMe(name)
  local mine = me()
  return mine ~= nil and name ~= nil and name:lower() == mine:lower()
end

-- ---------------------------------------------------------------- cards
local RANK = { T = 10, J = 11, Q = 12, K = 13, A = 14 }
local SUIT = { C = 1, D = 2, H = 3, S = 4 }
local FACE = { [10] = "10", [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
local SUITCH = { "C", "D", "H", "S" }

-- "[AD] [10H] [9H]" -> { {r=14, s=2}, ... }
function HS.parseCards(text)
  local cards = {}
  for r, s in text:gmatch("%[%s*([%dTJQKA]+)([CDHS])%s*%]") do
    local rank = RANK[r] or tonumber(r)
    if rank and rank >= 2 and rank <= 14 then cards[#cards + 1] = { r = rank, s = SUIT[s] } end
  end
  return cards
end

local function cardText(c) return (FACE[c.r] or tostring(c.r)) .. SUITCH[c.s] end
local function cardsText(cards)
  local out = {}
  for i, c in ipairs(cards) do out[i] = cardText(c) end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------- hand ranking
-- Best five of up to seven cards as one comparable number: category * 16^5 + tie-breakers
local B1, B2, B3, B4, B5 = 16, 256, 4096, 65536, 1048576
local RC, SC, SR, PR = {}, {}, {}, {}

local function straightHigh(p)
  local run = 0
  for r = 14, 1, -1 do
    if p[r == 1 and 14 or r] then
      run = run + 1
      if run >= 5 then return r + 4 end
    else
      run = 0
    end
  end
  return 0
end

-- The best `count` ranks present, skipping x1 and x2
local function kickers(count, x1, x2)
  local k1, k2, k3, k4, k5 = 0, 0, 0, 0, 0
  local got = 0
  for r = 14, 2, -1 do
    if RC[r] > 0 and r ~= x1 and r ~= x2 then
      got = got + 1
      if got == 1 then k1 = r elseif got == 2 then k2 = r elseif got == 3 then k3 = r
      elseif got == 4 then k4 = r else k5 = r end
      if got == count then break end
    end
  end
  return k1, k2, k3, k4, k5
end

function HS.eval(cards, n)
  n = n or #cards
  for r = 2, 14 do RC[r] = 0 end
  for s = 1, 4 do SC[s] = 0 end
  for i = 1, n do
    local c = cards[i]
    RC[c.r] = RC[c.r] + 1
    SC[c.s] = SC[c.s] + 1
  end
  local fs
  for s = 1, 4 do if SC[s] >= 5 then fs = s end end
  if fs then
    for r = 2, 14 do SR[r] = false end
    for i = 1, n do if cards[i].s == fs then SR[cards[i].r] = true end end
    local h = straightHigh(SR)
    if h > 0 then return 8 * B5 + h end
  end
  local q, t1, t2, p1, p2 = 0, 0, 0, 0, 0
  for r = 14, 2, -1 do
    local c = RC[r]
    if c == 4 then q = r
    elseif c == 3 then if t1 == 0 then t1 = r elseif t2 == 0 then t2 = r end
    elseif c == 2 then if p1 == 0 then p1 = r elseif p2 == 0 then p2 = r end end
  end
  if q > 0 then return 7 * B5 + q * B4 + kickers(1, q) * B3 end
  if t1 > 0 and (t2 > 0 or p1 > 0) then return 6 * B5 + t1 * B4 + math.max(t2, p1) * B3 end
  if fs then
    local score, mult, got = 5 * B5, B4, 0
    for r = 14, 2, -1 do
      if SR[r] then
        score, mult, got = score + r * mult, mult / 16, got + 1
        if got == 5 then break end
      end
    end
    return score
  end
  for r = 2, 14 do PR[r] = RC[r] > 0 end
  local h = straightHigh(PR)
  if h > 0 then return 4 * B5 + h end
  if t1 > 0 then
    local k1, k2 = kickers(2, t1)
    return 3 * B5 + t1 * B4 + k1 * B3 + k2 * B2
  end
  if p2 > 0 then return 2 * B5 + p1 * B4 + p2 * B3 + kickers(1, p1, p2) * B2 end
  if p1 > 0 then
    local k1, k2, k3 = kickers(3, p1)
    return B5 + p1 * B4 + k1 * B3 + k2 * B2 + k3 * B1
  end
  local k1, k2, k3, k4, k5 = kickers(5)
  return k1 * B4 + k2 * B3 + k3 * B2 + k4 * B1 + k5
end

HS.CATEGORY = { [0] = "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush",
                "Full House", "Four of a Kind", "Straight Flush" }

function HS.handName(cards)
  local score = HS.eval(cards)
  local cat = math.floor(score / B5)
  if cat == 8 and score % B5 == 14 then return "Royal Flush" end
  return HS.CATEGORY[cat]
end

-- What the hole cards add to the board, 0..5. A "Two Pair" made of a board pair and a
-- pocket pair below it is really one weak pair, and that's what matters for betting.
--   5 straight or better with your cards   4 two pair with both cards, a set, trips
--   3 top pair or an overpair               2 a weaker pair, or playing the board
--   1 a flush or straight draw              0 nothing
HS.STRENGTH = { [0] = "nothing", "a draw", "a weak pair", "top pair", "two pair or better", "a strong hand" }
function HS.strength(hole, board)
  local all = { hole[1], hole[2] }
  for _, c in ipairs(board) do all[#all + 1] = c end
  local cat = math.floor(HS.eval(all) / B5)
  local boardCat = #board >= 2 and math.floor(HS.eval(board) / B5) or 0
  if cat >= 4 then return boardCat >= cat and 2 or 5 end
  local cnt, top = {}, 0
  for _, c in ipairs(board) do cnt[c.r] = (cnt[c.r] or 0) + 1; top = math.max(top, c.r) end
  local a, b = hole[1].r, hole[2].r
  if a == b then
    if cnt[a] then return 4 end
    return a > top and 3 or 2
  end
  if cnt[a] and cnt[b] then return 4 end
  if (cnt[a] or 0) >= 2 or (cnt[b] or 0) >= 2 then return 4 end
  if cnt[a] or cnt[b] then return (cnt[a] and a or b) == top and 3 or 2 end
  if #board < 5 then
    local suits, ranks = {}, {}
    for _, c in ipairs(all) do suits[c.s] = (suits[c.s] or 0) + 1; ranks[c.r] = true end
    if (suits[hole[1].s] or 0) >= 4 or (suits[hole[2].s] or 0) >= 4 then return 1 end
    ranks[1] = ranks[14]
    for lo = 1, 10 do                              -- four of five in a row, using a hole card
      local have, mine = 0, false
      for r = lo, lo + 4 do
        if ranks[r] then
          have = have + 1
          if r == a or r == b or (r == 1 and (a == 14 or b == 14)) then mine = true end
        end
      end
      if have >= 4 and mine then return 1 end
    end
  end
  return 0
end

-- ---------------------------------------------------------------- starting hands
-- "AKs", "AKo", "TT"
local CLASSCH = { [10] = "T", [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
function HS.classOf(a, b)
  local hi, lo = math.max(a.r, b.r), math.min(a.r, b.r)
  local h, l = CLASSCH[hi] or tostring(hi), CLASSCH[lo] or tostring(lo)
  if hi == lo then return h .. l end
  return h .. l .. (a.s == b.s and "s" or "o")
end

local function set(list)
  local out = {}
  for w in list:gmatch("%S+") do out[w] = true end
  return out
end
HS.TIERS = {
  { name = "premium",  hands = set("AA KK QQ JJ AKs AKo") },
  { name = "strong",   hands = set("TT 99 AQs AQo AJs KQs") },
  { name = "good",     hands = set("88 77 ATs AJo KJs KQo QJs JTs") },
  { name = "playable", hands = set("66 55 44 33 22 A9s A8s A7s A6s A5s A4s A3s A2s KTs QTs T9s 98s KJo ATo QJo") },
}

-- 1 premium .. 4 playable, 5 for everything else
function HS.tier(hole)
  local class = HS.classOf(hole[1], hole[2])
  for i, t in ipairs(HS.TIERS) do if t.hands[class] then return i, t.name end end
  return 5, "weak"
end

-- Chen formula: orders starting hands, used to give opponents a range ("top 25%")
local function chen(a, b)
  local hi, lo = math.max(a.r, b.r), math.min(a.r, b.r)
  local pts = ({ [14] = 10, [13] = 8, [12] = 7, [11] = 6 })[hi] or hi / 2
  if hi == lo then return math.ceil(math.max(5, pts * 2)) end
  if a.s == b.s then pts = pts + 2 end
  local gap = hi - lo - 1
  pts = pts - (({ [0] = 0, 1, 2, 4 })[gap] or 5)
  if gap <= 1 and hi < 12 then pts = pts + 1 end
  return math.ceil(pts)
end

-- The Chen score that the top `pct` (0..1) of all 1326 starting hands reach
local chenSorted
local function rangeThreshold(pct)
  if pct >= 1 then return -99 end
  if not chenSorted then
    chenSorted = {}
    local deck = {}
    for r = 2, 14 do for s = 1, 4 do deck[#deck + 1] = { r = r, s = s } end end
    for i = 1, 52 do for j = i + 1, 52 do chenSorted[#chenSorted + 1] = chen(deck[i], deck[j]) end end
    table.sort(chenSorted, function(x, y) return x > y end)
  end
  return chenSorted[math.max(1, math.ceil(pct * #chenSorted))]
end

-- ---------------------------------------------------------------- equity
-- Chance to win (ties count as a share) against nOpp opponents, by dealing out `sims`
-- random finishes. Each opponent holds a hand from the top `range` (0..1) of starting
-- hands that, with the board so far, is at least mins[o] on the HS.strength scale: a
-- player who bet and re-raised has something, not any two cards.
function HS.equity(hole, board, nOpp, range, sims, mins)
  local dead = {}
  for _, c in ipairs(hole) do dead[c.r * 4 + c.s] = true end
  for _, c in ipairs(board) do dead[c.r * 4 + c.s] = true end
  local deck = {}
  for r = 2, 14 do
    for s = 1, 4 do
      if not dead[r * 4 + s] then deck[#deck + 1] = { r = r, s = s } end
    end
  end
  local thr = rangeThreshold(range or 1)
  local lists = {}
  local function combos(min)
    if lists[min] then return lists[min] end
    local out, any = {}, {}
    for i = 1, #deck do
      for j = i + 1, #deck do
        local x, y = deck[i], deck[j]
        if chen(x, y) >= thr then
          any[#any + 1] = { x, y }
          if min == 0 or HS.strength({ x, y }, board) >= min then out[#out + 1] = { x, y } end
        end
      end
    end
    lists[min] = #out > 0 and out or any            -- nothing fits: their range was a guess anyway
    return lists[min]
  end
  local ranges = {}
  for o = 1, nOpp do ranges[o] = combos(#board >= 3 and mins and mins[o] or 0) end

  local used, mine, theirs = {}, { hole[1], hole[2] }, {}
  for o = 1, nOpp do theirs[o] = {} end
  local nb, won = #board, 0
  local function free(c, sim) return used[c.r * 4 + c.s] ~= sim end
  local function use(c, sim) used[c.r * 4 + c.s] = sim; return c end
  local function draw(sim)
    while true do
      local c = deck[math.random(#deck)]
      if free(c, sim) then return use(c, sim) end
    end
  end

  for sim = 1, sims do
    for o = 1, nOpp do
      local list, a, b = ranges[o], nil, nil
      for _ = 1, 30 do
        local h = list[math.random(#list)]
        if free(h[1], sim) and free(h[2], sim) then a, b = use(h[1], sim), use(h[2], sim); break end
      end
      if not a then a, b = draw(sim), draw(sim) end
      theirs[o][1], theirs[o][2] = a, b
    end
    for i = 1, nb do
      mine[i + 2] = board[i]
      for o = 1, nOpp do theirs[o][i + 2] = board[i] end
    end
    for i = nb + 1, 5 do
      local c = draw(sim)
      mine[i + 2] = c
      for o = 1, nOpp do theirs[o][i + 2] = c end
    end
    local best, ties = HS.eval(mine, 7), 1
    local lost = false
    for o = 1, nOpp do
      local sc = HS.eval(theirs[o], 7)
      if sc > best then lost = true; break end
      if sc == best then ties = ties + 1 end
    end
    if not lost then won = won + 1 / ties end
  end
  return won / sims
end

-- ---------------------------------------------------------------- the decision
-- ctx: hole, board, toCall, pot, stack, bb, nOpp, minRaise (total), betOffer, canCheck,
-- noLimit, facingAllin. Returns { action, amount, command, why, equity, need, range }
local function sizeRaise(ctx, total)
  local cap = ctx.stack + (ctx.toCall or 0)
  if not ctx.noLimit then
    return ctx.toCall > 0 and "craise" or ("cbet " .. HS.amount(ctx.betOffer or ctx.bb)), "raise"
  end
  total = math.max(total, ctx.minRaise or ctx.bb)
  if total >= cap * 0.5 then return ctx.toCall > 0 and "craise all" or "cbet all", "all in" end
  local rounded = math.ceil(total / 25e6) * 25e6
  return (ctx.toCall > 0 and "craise " or "cbet ") .. HS.amount(rounded), (ctx.toCall > 0 and "raise to " or "bet ") .. brief(rounded)
end

local function passive(ctx, why, eq, need)
  if ctx.toCall == 0 then return { command = "ccheck", action = "check", why = why, equity = eq, need = need } end
  return { command = "cfold", action = "fold", why = why, equity = eq, need = need }
end

local function aggressive(ctx, total, why, eq, need)
  local command, action = sizeRaise(ctx, total)
  if not ctx.noLimit and ctx.toCall > 0 and not ctx.minRaise then  -- raises capped this round
    return { command = "ccall", action = "call", why = why .. " (no raise allowed)", equity = eq, need = need }
  end
  return { command = command, action = action, why = why, equity = eq, need = need }
end

local function call(ctx, why, eq, need)
  if ctx.toCall == 0 then return { command = "ccheck", action = "check", why = why, equity = eq, need = need } end
  return { command = "ccall", action = "call " .. brief(math.min(ctx.toCall, ctx.stack)), why = why, equity = eq, need = need }
end

-- What we need to win to call: the call over the pot after calling
local function potOdds(ctx)
  if ctx.toCall == 0 then return 0 end
  local callAmt = math.min(ctx.toCall, ctx.stack)
  local pot = ctx.pot - (ctx.toCall - callAmt)      -- what we can't cover goes back to them
  return callAmt / (pot + callAmt)
end

-- Worth half a bet from the small blind when nobody raised: suited cards, an ace or
-- king, or connected cards that make straights
function HS.completes(hole)
  local hi, lo = math.max(hole[1].r, hole[2].r), math.min(hole[1].r, hole[2].r)
  return hole[1].s == hole[2].s or hi >= 13 or (hi - lo <= 2 and lo >= 5)
end

function HS.decide(ctx)
  local bigBet = ctx.facingAllin or ctx.toCall >= ctx.stack / 3
  local need = potOdds(ctx)
  if #ctx.board == 0 then
    local tier, tname = HS.tier(ctx.hole)
    local m = ctx.stack / ctx.bb                    -- stack in big blinds
    local class = HS.classOf(ctx.hole[1], ctx.hole[2])
    if bigBet then
      -- an all in or a huge bet: they're strong (top 25%) - call only with the odds or a premium hand
      local eq = HS.equity(ctx.hole, ctx.board, 1, 0.25, ctx.sims)
      if tier == 1 and ctx.noLimit and ctx.minRaise and not ctx.facingAllin then
        return { command = "craise all", action = "all in", why = "premium " .. class .. " vs a big bet: all in",
                 equity = eq, need = need }
      end
      if tier == 1 or eq >= need + 0.03 then
        return call(ctx, tname .. " " .. class .. " vs a big bet: the odds are there", eq, need)
      end
      return passive(ctx, class .. " vs a big bet (their range: top 25%)", eq, need)
    end
    if m <= 10 and ctx.noLimit then
      -- short stack: all in or fold
      if tier <= 4 or ctx.hole[1].r == 14 or ctx.hole[2].r == 14 then
        return { command = ctx.toCall > 0 and "craise all" or "cbet all", action = "all in",
                 why = class .. " with " .. math.floor(m) .. " big blinds: push", need = need }
      end
      return passive(ctx, class .. " with " .. math.floor(m) .. " big blinds: fold and wait", nil, need)
    end
    if ctx.toCall <= ctx.bb and not ctx.raised then
      -- nobody raised yet (a min raise also leaves the big blind one big blind to call)
      if tier <= 3 then return aggressive(ctx, 3 * ctx.bb, tname .. " " .. class .. ": raise", nil, need) end
      -- playable hands open too from the button, or at a short table (4 players or fewer):
      -- only the blinds (or a couple of players) are left to beat
      if tier == 4 and (ctx.button or (ctx.players and ctx.players <= 4)) then
        return aggressive(ctx, 3 * ctx.bb, tname .. " " .. class .. (ctx.button and " on the button" or " at a short table") .. ": raise", nil, need)
      end
      -- heads up the small blind is the button (last to act after the flop): see most flops
      if ctx.toCall > 0 and ctx.toCall <= ctx.bb / 2 and (tier == 4 or ctx.nOpp == 1 or HS.completes(ctx.hole)) then
        return call(ctx, class .. ": half a bet to see a flop", nil, need)   -- small blind, limped pot
      end
      return passive(ctx, tname .. " " .. class, nil, need)
    end
    -- facing a raise
    if tier == 1 then return aggressive(ctx, 3 * ctx.toCall, "premium " .. class .. ": re-raise", nil, need) end
    if tier <= 3 and ctx.toCall <= ctx.stack * 0.1 then return call(ctx, tname .. " " .. class .. " vs a raise", nil, need) end
    -- a playable hand calls a small raise when the pot pays for it (against a raiser's range)
    if tier == 4 and ctx.toCall <= ctx.stack * 0.1 then
      local eq = HS.equity(ctx.hole, ctx.board, ctx.nOpp, 0.3, ctx.sims)
      if eq >= need + 0.03 then return call(ctx, tname .. " " .. class .. " vs a raise: the pot odds say call", eq, need) end
      return passive(ctx, tname .. " " .. class .. " vs a raise: not the odds", eq, need)
    end
    return passive(ctx, tname .. " " .. class .. " vs a raise", nil, need)
  end

  -- after the flop: their range narrows with the size of the bet they made (starting
  -- hands), and with how they've bet this hand (what they must have with this board)
  local range = 0.7
  if ctx.toCall > 0 then
    local ratio = ctx.toCall / math.max(1, ctx.pot - ctx.toCall)
    range = (ctx.facingAllin or ratio >= 1) and 0.25 or ratio >= 0.5 and 0.4 or 0.6
  end
  local mins = ctx.oppMins or {}
  local eq = HS.equity(ctx.hole, ctx.board, ctx.nOpp, range, ctx.sims, mins)
  local all = { ctx.hole[1], ctx.hole[2] }
  for _, c in ipairs(ctx.board) do all[#all + 1] = c end
  local made, mine = HS.handName(all), HS.strength(ctx.hole, ctx.board)
  if mine <= 2 and made ~= "Pair" and made ~= "High Card" then
    made = made .. " (mostly the board: " .. HS.STRENGTH[mine] .. ")"
  end
  local theyPush = 0                                 -- the most an opponent still in has bet and raised
  for _, m in ipairs(mins) do theyPush = math.max(theyPush, m) end
  local strong = math.max(0.6, math.min(0.8, 2 / (ctx.nOpp + 1)))
  if ctx.toCall == 0 then
    local valueBet = math.max(0.45, math.min(0.65, 1.6 / (ctx.nOpp + 1)))
    if eq >= valueBet then
      -- one pair bets small, more so on the turn and river: a big bet only gets called (or
      -- raised) by what beats it, and a raise would leave a choice for the whole stack
      if mine <= 3 then
        local size = #ctx.board == 3 and ctx.pot / 2 or ctx.pot / 3
        size = math.min(size, ctx.stack * 0.15)
        return aggressive(ctx, math.floor(size), made .. ": small bet for value", eq, need)
      end
      return aggressive(ctx, math.floor(ctx.pot * 2 / 3), made .. ": bet for value", eq, need)
    end
    return passive(ctx, made .. ": check", eq, need)
  end
  -- They've bet and raised into you: only two pair or better raises back. One pair calls
  -- if the odds are there - a raise war with one pair is how a stack goes.
  local capped = theyPush >= 3 and mine < 4
  if eq >= strong and not bigBet and not capped then
    return aggressive(ctx, 3 * ctx.toCall, made .. ": well ahead, raise", eq, need)
  end
  local why = capped and (made .. ": they keep raising, call only") or (made .. ": the pot odds say call")
  if eq >= need + 0.03 then return call(ctx, why, eq, need) end
  return passive(ctx, made .. ": not enough to call", eq, need)
end

-- ---------------------------------------------------------------- the table
-- "The High Stakes Dealer pitches two cards to each player." / new hand
function HS.newHand()
  HS.hand = newHand()
  HS.stats.hands = HS.stats.hands + 1
end

-- "New hand! Vorricer has the button." (comes before the cards, so kept outside HS.hand)
function HS.onButton(name) HS.button = name end

function HS.onHandStart(handNo, sb, bb)
  HS.handNo = tonumber(handNo)
  HS.bb = num(bb)
  if HS.handNo and HS.handNo >= 11 then HS.early = false end
end

-- "Your cards: [KS] [AC]" (alone, or in the table display)
function HS.onHole(text)
  local cards = HS.parseCards(text)
  if #cards == 2 then HS.hand.hole = cards end
end

-- "The flop: [9S] [10S] [7D]" / "The turn: [6S]" / "The river: [AH]"
function HS.onStreet(street, text)
  local cards = HS.parseCards(text)
  if street == "flop" then HS.hand.board = cards
  else for _, c in ipairs(cards) do HS.hand.board[#HS.hand.board + 1] = c end end
end

-- Players we hear about between table displays (preflop, before the first display)
local function seat(name)
  for _, n in ipairs(HS.seats) do if n == name then return end end
  HS.seats[#HS.seats + 1] = name
end

-- The table display: " High Stakes Tournament  Level 3  Blinds: 100,000,000/200,000,000 ..."
function HS.onTableStart(text)
  HS.seats = {}
  local bb = text and text:match("Blinds: [%d,]+/([%d,]+)")
  if bb then HS.bb = num(bb) end
end
function HS.onBoard(text)
  local cards = HS.parseCards(text)
  if #cards >= 3 then HS.hand.board = cards end
end
-- "  Snuggles     stack 9,900,000,000  bet 100,000,000 (button)", " >Carolina ... to act",
-- "  Vorrac       stack 0              all in", "  Vorrac  stack 10,150,000,000 folded"
function HS.onSeat(name, stack, rest)
  rest = rest or ""
  HS.stacks[name] = num(stack)
  local allin = rest:find("all in", 1, true) ~= nil
  if num(stack) > 0 or allin then seat(name) end
  if rest:find("folded", 1, true) then HS.hand.folded[name] = true end
  if allin then HS.hand.allin[name] = true end
end
function HS.onEarly(text) HS.early = text:find("Early limits", 1, true) ~= nil end

-- "The High Stakes Dealer says, 'Action is on Vorricer.'"
function HS.onActionOn(name)
  HS.actionOn = name
  seat(name)
end

-- "Cicada folds." / "... raises to 9,300,000,000 and is all in!"
function HS.onPlay(name, verb, rest)
  if name == "Everyone" then return end            -- "Everyone folds. Cicada takes the pot..."
  seat(name)
  if verb == "folds" then HS.hand.folded[name] = true end
  if #HS.hand.board < 3 and verb == "raises" then HS.hand.preRaise = true end   -- someone raised preflop
  if #HS.hand.board >= 3 then                      -- after the flop: how they're playing this board
    if verb == "bets" or verb == "raises" then HS.hand.aggr[name] = (HS.hand.aggr[name] or 0) + 1 end
    if verb == "calls" then HS.hand.called[name] = true end
    if verb == "raises" then HS.hand.raised[name] = true end
    if rest and rest:find("all in", 1, true) and verb ~= "calls" then HS.hand.shoved[name] = true end
  end
  if rest and rest:find("all in", 1, true) then
    HS.hand.allin[name] = true
    local p = HS.players[name] or { allins = 0, shows = {} }
    p.allins = p.allins + 1
    HS.players[name] = p
  end
  if isMe(name) then HS.hand.turn = nil end        -- our move went through
end

-- "Cicada shows [6H] [9D]: Two Pair."
function HS.onShow(name, text)
  local p = HS.players[name] or { allins = 0, shows = {} }
  table.insert(p.shows, 1, cardsText(HS.parseCards(text)) .. ": " .. (text:match(":%s*(.-)%.?$") or ""))
  while #p.shows > 5 do table.remove(p.shows) end
  HS.players[name] = p
end

-- "Stryfe wins the pot of 2,025,000,000 (Full House)." / "Everyone folds. Cicada takes the pot of 375,000,000."
function HS.onPotWon(name, amount)
  if isMe(name) then
    HS.stats.won = HS.stats.won + 1
    HS.stats.wonZenni = HS.stats.wonZenni + num(amount)
  end
end

-- "Vorrac is out of time and checks." / "... and folds."
function HS.onTimeout(name, verb) HS.onPlay(name, verb) end

-- "[CKMud Info]: The Friday High Stakes tournament begins with 3 players: Snuggles, Carolina and Vorrac."
function HS.onTourneyStart(list)
  HS.seats, HS.hand, HS.out, HS.place = {}, newHand(), false, nil
  for name in list:gsub(" and ", ", "):gmatch("[^,%s]+") do seat(name) end
  info("cyan", "Tournament with " .. #HS.seats .. " players: " .. table.concat(HS.seats, ", "))
end

-- "[CKMud Info]: Vorrac is knocked out of the High Stakes tournament in 3rd place."
function HS.onKnockout(name, place)
  for i, n in ipairs(HS.seats) do if n == name then table.remove(HS.seats, i); break end end
  if isMe(name) then
    HS.out, HS.place, HS.hand.turn = true, place, nil
    HS.stats.finishes = (HS.stats.finishes or "") .. (HS.stats.finishes and ", " or "") .. place
    info("yellow", "Out in " .. place .. " place")
  end
end

-- "You're out of chips and out of the High Stakes tournament."
function HS.onOut() HS.out, HS.hand.turn = true, nil end

-- Opponents still in the hand
function HS.opponentNames()
  local out = {}
  for _, name in ipairs(HS.seats) do
    if not isMe(name) and not HS.hand.folded[name] then out[#out + 1] = name end
  end
  return out
end
function HS.opponents() return math.max(1, #HS.opponentNames()) end

-- What a player must hold, on the HS.strength scale, given how they've bet after the flop:
-- called a bet = a pair or a draw, bet or raised once = the same, twice = top pair, three
-- times or more (bet, bet, raise...) = two pair or better
-- A raise over a bet says more than a bet: top pair at least, and a raise or bet that puts
-- them all in after the flop is two pair or better (a big shove is rarely a bluff).
function HS.minStrength(name)
  local h = HS.hand
  local a = h.aggr[name] or 0
  if a >= 3 or (h.shoved and h.shoved[name]) then return 4 end
  if h.raised and h.raised[name] then return 3 end
  if a == 2 then return 3 end
  if a == 1 or HS.hand.called[name] then return 1 end
  return 0
end

-- "Your turn: 75,000,000 to call. ccall, craise to 150,000,000, or cfold."
function HS.onYourTurn(text)
  if HS.actionOn and not me() then HS.me = HS.actionOn end   -- the action was on us
  local t = { text = text }
  t.toCall = num(text:match("([%d,]+) to call") or 0)
  t.canCheck = text:find("ccheck", 1, true) ~= nil
  t.betOffer = text:match("cbet ([%d,]+)") and num(text:match("cbet ([%d,]+)"))
  t.minRaise = text:match("craise to ([%d,]+)") and num(text:match("craise to ([%d,]+)"))
  t.noLimit = text:find("or more", 1, true) ~= nil or (not HS.early and not t.minRaise and not t.betOffer)
  if t.canCheck then t.toCall = 0 end
  HS.hand.turn = t
end

-- "TOURNEY: Your turn. 75M to call. Pot 1B. Stack 9.6B. Level 2 (75M/150M). 30 seconds."
-- Comes after the Your turn line (and repeats): it has the pot, so advise now (once a turn).
function HS.onTourneyTurn(text)
  local t = HS.hand.turn
  if not t then return end
  t.pot = HS.short(text:match("Pot ([%d%.]+[KMB]?)") or "") or t.pot
  t.stack = HS.short(text:match("Stack ([%d%.]+[KMB]?)") or "") or t.stack
  if t.advice or not HS.enabled then return end
  HS.advise()
end

function HS.advise()
  local t, h = HS.hand.turn, HS.hand
  if not t then return info("yellow", "It isn't your turn") end
  if not h.hole then return info("yellow", "Didn't see your cards - type ctable") end
  local stack = t.stack or (me() and HS.stacks[me()]) or 0  -- the TOURNEY line is the current one
  local facingAllin = false
  for name in pairs(h.allin) do if not h.folded[name] and not isMe(name) then facingAllin = true end end
  local ctx = {
    hole = h.hole, board = h.board, toCall = t.toCall, pot = t.pot or (t.toCall * 2), stack = math.max(stack, 1),
    bb = HS.bb, nOpp = HS.opponents(), minRaise = t.minRaise, betOffer = t.betOffer,
    canCheck = t.canCheck, noLimit = t.noLimit, facingAllin = facingAllin, sims = HS.sims,
    players = #HS.seats > 0 and #HS.seats or nil, button = HS.button ~= nil and isMe(HS.button),
    raised = HS.hand.preRaise,
  }
  ctx.oppMins = {}
  for i, name in ipairs(HS.opponentNames()) do ctx.oppMins[i] = HS.minStrength(name) end
  t.advice = HS.decide(ctx)
  HS.show()
end

function HS.show(urgent)
  local t, h = HS.hand.turn, HS.hand
  if not (t and t.advice) then return info("white", "No advice yet (it shows on your turn)") end
  local a = t.advice
  local cards = cardsText(h.hole)
  if #h.board > 0 then cards = cards .. "  <grey>on<white> " .. cardsText(h.board) end
  cecho("\n<cyan>[hs] <white>" .. cards .. "\n")
  local line = "     "
  if a.equity then
    line = line .. string.format("Win %d%% vs %d", math.floor(a.equity * 100 + 0.5), HS.opponents())
  end
  if t.toCall > 0 then
    line = line .. string.format("<grey> | <white>%s to call, pot %s: need %d%%", brief(t.toCall), brief(t.pot or 0),
      math.floor((a.need or 0) * 100 + 0.5))
  end
  if line ~= "     " then cecho(line .. "\n") end
  cecho("     <" .. (urgent and "red" or "yellow") .. ">" .. a.action:upper() .. "<white>  " .. a.why ..
    "   <grey>(hs go: " .. a.command .. ")\n")
end

-- "The High Stakes Dealer says, 'Vorricer, ten seconds.'"
-- Shows the advice in red and, with hs auto on, plays it so the turn isn't lost.
function HS.onTenSeconds(name)
  local t = HS.hand.turn
  if not (isMe(name) and t) then return end
  if not t.advice and HS.hand.hole then HS.advise() end   -- (advice off: work it out now)
  if not t.advice then return end
  HS.show(true)
  if HS.autoGo and not t.sent then
    t.sent = true
    info("red", "Ten seconds left: playing " .. t.advice.command)
    send(t.advice.command)
  end
end

-- ---------------------------------------------------------------- `hs` alias
HS.HELP = {
  { "hs",              "Show the advice for this turn again" },
  { "hs go",           "Send the suggested move (ccall, craise 450m, cfold...)" },
  { "hs on|off",       "Show advice on your turns (default on)" },
  { "hs auto on|off",  "At the dealer's ten seconds warning, play the suggestion for you (default on)" },
  { "hs sims <n>",     "Simulated deals per decision (default 3000; fewer is faster)" },
  { "hs players",      "How often each player went all in, and what they showed" },
  { "hs status",       "Hands seen and pots won" },
  { "hs reset",        "Clear stats and player notes" },
  { "hs help",         "Show this list" },
}

function HS.command(cmd, arg)
  if cmd == nil then
    HS.show()
  elseif cmd == "help" then
    cecho("\n<cyan>High Stakes advisor (hs) commands:\n")
    for _, row in ipairs(HS.HELP) do cecho(string.format("  <yellow>%-16s<white>%s\n", row[1], row[2])) end
    cecho("  <white>It only moves by itself at the ten seconds warning (<yellow>hs auto off<white> to stop that).\n")
  elseif cmd == "go" then
    local t = HS.hand.turn
    if not (t and t.advice) then return info("yellow", "No move to send - it isn't your turn") end
    t.sent = true
    send(t.advice.command)
  elseif cmd == "auto" and (arg == "on" or arg == "off") then
    HS.autoGo = arg == "on"
    info("white", "Auto play at ten seconds " .. arg)
  elseif cmd == "on" or cmd == "off" then
    HS.enabled = cmd == "on"
    info("white", "Advice " .. cmd)
  elseif cmd == "sims" and tonumber(arg) then
    HS.sims = math.max(200, math.floor(tonumber(arg)))
    info("white", "Simulated deals per decision: " .. HS.sims)
  elseif cmd == "players" then
    cecho("\n<cyan>hs players:\n")
    for name, p in pairs(HS.players) do
      cecho(string.format("  <white>%-12s all in %d time%s%s\n", name, p.allins, p.allins == 1 and "" or "s",
        #p.shows > 0 and ("   showed: " .. table.concat(p.shows, ", ")) or ""))
    end
  elseif cmd == "status" then
    cecho(string.format("\n<cyan>hs status:\n  <white>Advice %s   hands %d   pots won %d (%s)   big blind %s%s\n",
      HS.enabled and "on" or "off", HS.stats.hands, HS.stats.won, brief(HS.stats.wonZenni), brief(HS.bb),
      HS.early and "   early limits" or ""))
    if HS.stats.finishes then cecho("  <white>Finished: " .. HS.stats.finishes .. "\n") end
  elseif cmd == "reset" then
    HS.stats, HS.players = newStats(), {}
    info("white", "Stats and player notes cleared")
  else
    info("yellow", "Unknown command. Type hs help")
  end
end

casino.register{
  key = "hs", title = "High Stakes", command = "hs",   -- an advisor: never "playing", so it gets no rewards
  status = function()
    return string.format("advice %s, %d hands, %d pots won (%s)", HS.enabled and "on" or "off",
      HS.stats.hands, HS.stats.won, brief(HS.stats.wonZenni))
  end,
}
