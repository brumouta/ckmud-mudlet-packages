-- vp: card parsing, scoring, strategy, and the machine flow from real game output.
-- Run from the repo root: lua tests/VideoPoker_test.lua
local now, timers, nextId, sent, deleted = 0, {}, 0, {}, 0
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function deleteLine() deleted = deleted + 1 end
function alert() ALERTED = true end
function tempTimer(d, f) nextId = nextId + 1; timers[nextId] = { at = now + d, f = f }; return nextId end
function killTimer(i) timers[i] = nil end
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
local function took() local s = table.concat(sent, " | "); sent = {}; return s end

dofile("packages/VideoPoker/src/VideoPoker.lua")

-- The game: lines go through the same triggers as package.json
local PAYROW = { "Royal Flush", "Straight Flush", "Four of a Kind", "Full House", "Flush", "Straight",
                 "Three of a Kind", "Two Pair", "Jacks or Better" }
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    line = l
    local stripped = l:gsub("%[[%dTJQKA]+[CDHS]%]", ""):gsub("%s", "")
    local _, n = l:gsub("%[[%dTJQKA]+[CDHS]%]", "")
    if n == 5 and stripped == "" then vp.onCards(l) end
    local z, c = l:match("^You feed ([%d,]+) zenni into the machine for (%d+) coins?")
    if z then vp.onFeed(z, c) end
    local cr = l:match("^%s*Credit: ([%d,]+) zenni")
    if cr then vp.onCredit(cr, l) end
    if l:find("Type 'vpoker hold <positions>' to keep cards", 1, true) then vp.onHoldPrompt() end
    local gag = l:match("^o%-+o$") or l:match("^%s+JACKS OR BETTER") or l:match("^%s+Hand%s+1%s+2%s+3%s+4%s+5%s*$")
    for _, name in ipairs(PAYROW) do
      if l:match("^%s+" .. name .. "%s+[%d,]+%s+[%d,]+%s+[%d,]+") then gag = true end
    end
    if gag then vp.gag() end
    local t = l:match("^You earn ([%d,]+) Lucky Tails"); if t then vp.luckyTails(t) end
    local x = l:match("^You have gained ([%d,]+) strength XP"); if x then vp.xpGained(x) end
  end
end

local PAYTABLE = [[o--------------------------------------------------o
  JACKS OR BETTER VIP        coin 5,000,000 zenni
  Hand                 1     2     3     4      5
  Royal Flush         250   500   750 1,000  4,000
  Straight Flush       50   100   150   200    250
  Four of a Kind       25    50    75   100    125
  Full House            8    16    24    32     40
  Flush                 5    10    15    20     25
  Straight              4     8    12    16     20
  Three of a Kind       3     6     9    12     15
  Two Pair              2     4     6     8     10
  Jacks or Better       1     2     3     4      5
o--------------------------------------------------o]]
-- The real deal screen
local function dealScreen(cards, credit)
  return "You feed 25,000,000 zenni into the machine for 5 coins.\n" .. PAYTABLE .. "\n" ..
    "  " .. cards .. "\n                                                  \n" ..
    "   1         2         3         4         5      \n" ..
    "  Credit: " .. credit .. " zenni   Bet: 5 coins (25,000,000 zenni)\n" ..
    "  Type 'vpoker hold <positions>' to keep cards, then 'vpoker draw'."
end
-- A guess at the draw screen (not seen yet): paytable, cards, credit
local function drawScreen(cards, credit)
  return PAYTABLE .. "\n  " .. cards .. "\n   1         2         3         4         5      \n" ..
    "  Credit: " .. credit .. " zenni"
end
local function C(s) return vp.parseCards(s) end
local function decide(s) local h, why = vp.decide(C(s)); return table.concat(h), why end

-- Cards ------------------------------------------------------------------------
local cards = C("  [3C]      [JC]      [QS]      [10D]     [KH]    ")
ok(#cards == 5 and cards[1].r == 3 and cards[4].r == 10 and cards[4].s == "D" and cards[5].text == "KH",
   "reads the five cards, 10 included")
ok(#C("[AS] [TS]") == 2 and C("[TS]")[1].r == 10, "T also means 10")

-- Scoring ---------------------------------------------------------------------
local scores = {
  { "[10S] [JS] [QS] [KS] [AS]", "royal" }, { "[9H] [10H] [JH] [QH] [KH]", "sflush" },
  { "[AC] [2C] [3C] [4C] [5C]", "sflush" }, { "[7S] [7H] [7D] [7C] [2S]", "quads" },
  { "[7S] [7H] [7D] [2C] [2S]", "fullhouse" }, { "[2H] [7H] [9H] [JH] [KH]", "flush" },
  { "[AC] [2D] [3H] [4S] [5C]", "straight" }, { "[10C] [JD] [QH] [KS] [AC]", "straight" },
  { "[QC] [KD] [AH] [2S] [3C]", "nothing" }, { "[7S] [7H] [7D] [2C] [3S]", "trips" },
  { "[7S] [7H] [2D] [2C] [3S]", "twopair" }, { "[JS] [JH] [2D] [5C] [3S]", "jacks" },
  { "[10S] [10H] [2D] [5C] [3S]", "nothing" },
}
for _, c in ipairs(scores) do
  ok(vp.score(C(c[1])) == c[2], c[1] .. " is " .. c[2])
end
ok(vp.payout("royal", 5) == 4000 and vp.payout("royal", 4) == 1000 and vp.payout("fullhouse", 5) == 40,
   "paytable, royal jumps to 4,000 at five coins")

-- Strategy (Jacks or Better 8/5) -----------------------------------------------
local plays = {
  { "[3C] [JC] [QS] [10D] [KH]", "2345", "10-J-Q-K" },                    -- the hand from the screen
  { "[10S] [JS] [QS] [KS] [2S]", "1234", "4 to a royal flush" },          -- breaks a flush
  { "[10S] [JS] [QS] [KS] [9D]", "1234", "4 to a royal flush" },          -- breaks a straight
  { "[JS] [JH] [QS] [KS] [AS]", "1345", "4 to a royal flush" },           -- breaks a high pair
  { "[2H] [7H] [9H] [JH] [KH]", "12345", "pat full house, flush or straight" },
  { "[7S] [7H] [7D] [2C] [3S]", "123", "three of a kind" },
  { "[5S] [6S] [7S] [8S] [KD]", "1234", "4 to a straight flush" },
  { "[7S] [7H] [2D] [2C] [KS]", "1234", "two pair" },
  { "[JS] [JH] [2S] [5S] [9S]", "12", "high pair" },                      -- over 4 to a flush
  { "[2D] [JS] [QS] [KS] [9H]", "234", "3 to a royal flush" },
  { "[2S] [5S] [9S] [KS] [KD]", "45", "high pair" },
  { "[2S] [5S] [9S] [7S] [3D]", "1234", "4 to a flush" },
  { "[4C] [4D] [5S] [6H] [7C]", "12", "low pair" },                       -- over an outside straight
  { "[4C] [5D] [6S] [7H] [KC]", "1234", "4 to an outside straight" },
  { "[8S] [9S] [10S] [2D] [3C]", "123", "3 to a straight flush" },
  { "[QS] [JS] [4D] [7C] [2H]", "12", "suited Q-J" },
  { "[JC] [QD] [KH] [AS] [3C]", "1234", "J-Q-K-A" },
  { "[KD] [QD] [AS] [3C] [6H]", "12", "suited K-Q or K-J" },
  { "[QC] [KD] [AH] [3S] [7C]", "12", "2 high cards" },                   -- the two lowest
  { "[JC] [8D] [5H] [3S] [2C]", "1", "one high card" },
  { "[2C] [4D] [6H] [8S] [9C]", "", "nothing worth keeping" },
  { "[2C] [5C] [6C] [9D] [10H]", "123", "3 to a straight flush (weakest)" },
}
for _, p in ipairs(plays) do
  local hold, why = decide(p[1])
  ok(hold == p[2] and why == p[3], p[1] .. " -> hold " .. (p[2] == "" and "nothing" or p[2]) .. " (" .. p[3] .. ")" ..
     ((hold ~= p[2] or why ~= p[3]) and ("  GOT " .. hold .. " " .. why) or ""))
end

-- The machine ------------------------------------------------------------------
vp.command("start")
ok(took() == "vpoker", "vp start looks at the machine first")
feed("  Credit: 261,451,214,676 zenni")                             -- no hand waiting
wait(2)
ok(took() == "vpoker deal", "nothing on the table: deals five coins")

deleted = 0
feed(dealScreen("[3C]      [JC]      [QS]      [10D]     [KH]", "261,426,214,676"))
ok(deleted == 13, "the paytable is hidden while the bot plays")
ok(vp.stats.startCredit == 261451214676, "starting credit is the credit before the bet")
wait(1)
ok(took() == "vpoker draw 2345", "holds J Q 10 K and draws in one command")

feed(drawScreen("[9C]      [JC]      [QS]      [10D]     [KH]", "261,526,214,676"))
wait(1)
ok(vp.stats.hands == 1 and vp.stats.byHand.straight == 1 and vp.stats.coinsWon == 20, "scores the drawn straight: 20 coins")
ok(LOG:find("Straight %+20 coins") and LOG:find("net %+75,000,000 zenni"), "prints the result and the real net from the credit")
ok(took() == "vpoker deal", "and deals the next hand")

-- Credit line before the cards on the draw screen: the cards are read after a short wait
feed(dealScreen("[2C]      [4D]      [6H]      [8S]      [9C]", "261,501,214,676"))
wait(1)
ok(took() == "vpoker hold none | vpoker draw", "nothing worth keeping: releases every card, then draws")
feed("  Credit: 261,501,214,676 zenni\n  [JC]      [JD]      [3H]      [4S]      [7C]")
wait(1)
ok(vp.stats.hands == 2 and vp.stats.byHand.jacks == 1, "cards after the credit line are still the ones scored")
took()

-- Lag: no answer to the deal, so it looks; the hand is waiting on the table, so it plays it
wait(10)
ok(took() == "vpoker", "no answer for 10 seconds: looks at the machine")
feed(PAYTABLE .. "\n  [AS]      [KS]      [QS]      [JS]      [3D]\n" ..
     "  Credit: 261,476,214,676 zenni   Bet: 5 coins (25,000,000 zenni)\n" ..
     "  Type 'vpoker hold <positions>' to keep cards, then 'vpoker draw'.")
wait(3)
ok(took() == "vpoker draw 1234", "plays the hand it found instead of dealing over it")
feed(drawScreen("[AS]      [KS]      [QS]      [JS]      [10S]", "261,576,214,676"))
wait(1)
ok(vp.stats.byHand.royal == 1 and vp.stats.coinsWon == 20 + 5 + 4000 and ALERTED, "royal flush: 4,000 coins and a flash")
took()

-- Rewards
feed("You earn 100 Lucky Tails!\nYou have gained 120,000 strength XP.")
ok(vp.stats.tails == 100 and vp.stats.xp == 120000, "Lucky Tails and STR XP are counted")

-- vp stop finishes the hand on the table
feed(dealScreen("[7S]      [7H]      [2D]      [2C]      [KS]", "261,551,214,676"))
vp.command("stop")
wait(1)
ok(took() == "vpoker draw 1234", "vp stop: the dealt hand is still drawn")
feed(drawScreen("[7S]      [7H]      [2D]      [2C]      [KS]", "261,561,214,676"))
wait(5)
ok(took() == "" and not vp.active, "then it stops instead of dealing")
deleted = 0
feed(PAYTABLE)
ok(deleted == 0, "the paytable shows again once the bot is off")

-- Limits
ok(vp.parseAmount("500m") == 500000000 and vp.parseAmount("1.5b") == 1500000000 and vp.parseAmount("25,000") == 25000
   and vp.parseAmount("lots") == nil, "amounts: 500m, 1.5b, 25,000")
vp.command("stoploss", "50m")
vp.command("start"); took()
feed("  Credit: 261,561,214,676 zenni"); wait(2); took()
feed(dealScreen("[2C]      [4D]      [6H]      [8S]      [9C]", "261,536,214,676")); wait(1); took()
feed(drawScreen("[3C]      [5D]      [7H]      [10S]     [QC]", "261,536,214,676")); wait(1)
ok(took() == "vpoker deal", "down 25m with a 50m stop loss: keeps going")
feed(dealScreen("[2C]      [4D]      [6H]      [8S]      [9C]", "261,511,214,676")); wait(1); took()
feed(drawScreen("[3C]      [5D]      [7H]      [10S]     [QC]", "261,511,214,676")); wait(1)
ok(took() == "" and not vp.active and LOG:find("stop loss"), "down 50m: stops")
vp.command("stoploss", "0")

-- Gives up if the machine never answers
vp.command("start"); took()
wait(60)
ok(not vp.active and LOG:find("stopped answering"), "gives up after the machine doesn't answer 3 looks in a row")

vp.command("advise"); ok(LOG:find("vpoker draw"), "vp advise shows the play for the cards on screen")
vp.command("coins", "3"); vp.command("start"); took(); feed("  Credit: 100,000,000,000 zenni"); wait(2)
ok(took() == "vpoker deal 3", "vp coins 3 bets three coins"); vp.command("stop", "now")
vp.command("help"); vp.command("status"); vp.command("bogus")
print("\nvp: ALL PASSED")
