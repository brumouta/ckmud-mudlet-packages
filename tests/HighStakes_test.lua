-- hs: hand ranking, equity, the advice, and a real tournament log replayed through the triggers.
-- Run from the repo root: lua tests/HighStakes_test.lua
math.randomseed(7)
local sent = {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end

dofile("packages/Casino/src/Core.lua")
dofile("packages/Casino/src/HighStakes.lua")
local C = hs.parseCards

-- Hand ranking ------------------------------------------------------------------
local names = {
  { "[AS] [KS] [QS] [JS] [10S] [2D] [3C]", "Royal Flush" }, { "[9H] [8H] [7H] [6H] [5H] [AD] [AC]", "Straight Flush" },
  { "[AH] [2H] [3H] [4H] [5H] [9C] [9D]", "Straight Flush" }, { "[7S] [7H] [7D] [7C] [AS] [KD] [2C]", "Four of a Kind" },
  { "[AD] [10H] [9H] [6S] [AH] [10D] [10S]", "Full House" }, { "[2H] [7H] [9H] [JH] [KH] [KD] [KS]", "Flush" },
  { "[AC] [2D] [3H] [4S] [5C] [KD] [KS]", "Straight" }, { "[AD] [10H] [9H] [6S] [AH] [KS] [AC]", "Three of a Kind" },
  { "[AD] [10H] [9H] [6S] [AH] [6H] [9D]", "Two Pair" }, { "[2S] [2C] [5D] [9H] [KS]", "Pair" },
  { "[2S] [4C] [6D] [9H] [KS] [JD] [8C]", "High Card" },
}
for _, n in ipairs(names) do ok(hs.handName(C(n[1])) == n[2], n[1] .. " is a " .. n[2]) end
-- the showdown from the log: Stryfe's full house > Vorricer's trips > Cicada's two pair
local board = "[AD] [10H] [9H] [6S] [AH] "
local stryfe, vorr, cic = hs.eval(C(board .. "[10D] [10S]")), hs.eval(C(board .. "[KS] [AC]")), hs.eval(C(board .. "[6H] [9D]"))
ok(stryfe > vorr and vorr > cic, "the log's showdown ranks the same way the dealer did")
ok(hs.eval(C("[AS] [AD] [KC] [9D] [2H]")) > hs.eval(C("[AS] [AD] [QC] [9D] [2H]")), "kickers count")
ok(hs.eval(C("[5S] [4D] [3C] [2D] [AH]")) < hs.eval(C("[6S] [5D] [4C] [3D] [2H]")), "the wheel is the lowest straight")

-- Equity ------------------------------------------------------------------------
local function near(x, want, tol) return math.abs(x - want) <= tol end
local e = hs.equity(C("[AS] [AD]"), {}, 1, 1, 4000)
ok(near(e, 0.85, 0.03), string.format("AA vs a random hand: %.1f%% (about 85%%)", e * 100))
local random22 = hs.equity(C("[2S] [2C]"), {}, 1, 1, 4000)
ok(near(random22, 0.50, 0.03), string.format("22 vs a random hand: %.1f%% (about 50%%)", random22 * 100))
e = hs.equity(C("[2S] [2C]"), {}, 1, 0.10, 4000)   -- across 40 seeds the gap is 6.6 to 12 points
ok(e < random22 - 0.03, string.format("22 vs a top 10%% hand: %.1f%% (worse than vs a random one)", e * 100))
e = hs.equity(C("[KS] [AC]"), C(board), 2, 1, 2000)
ok(e > 0.78, string.format("trip aces on the river vs 2 random hands: %.1f%%", e * 100))
ok(hs.amount(450e6) == "450m" and hs.amount(2.5e9) == "2.5b" and hs.amount(3e9) == "3b" and hs.amount(2450e6) == "2450m",
   "bet amounts: 450m, 2.5b, 3b")
ok(hs.short("1.1B") == 1100000000 and hs.short("225M") == 225000000, "pot and stack from the TOURNEY line")

-- The log -----------------------------------------------------------------------
local advice = {}
local function feed(l)
  line = l
  if l:find("The High Stakes Dealer pitches two cards to each player.", 1, true) then hs.newHand() end
  local h, sb, bb = l:match("Hand (%d+), blinds ([%d,]+) and ([%d,]+)%.")
  if h then hs.onHandStart(h, sb, bb) end
  local hole = l:match("^%s*Your cards: (.+)$"); if hole then hs.onHole(hole) end
  local st, sc = l:match("^The High Stakes Dealer says, 'The (%a+): (.+)'")
  if st then hs.onStreet(st, sc) end
  if l:match("^%s*High Stakes Tournament%s+Level") then hs.onTableStart(l) end
  local b = l:match("^%s*Board: (.+)$"); if b then hs.onBoard(b) end
  local sn, ss, srest = l:match("^%s+>?(%w+)%s+stack ([%d,]+)(.*)$"); if sn then hs.onSeat(sn, ss, srest) end
  if l:match("^%s*Players left: %d+") or l:find("The early limits are off.", 1, true) then hs.onEarly(l) end
  local a = l:match("^The High Stakes Dealer says, 'Action is on (%w+)%.'"); if a then hs.onActionOn(a) end
  local pn, pv, pr = l:match("^The High Stakes Dealer %a+, '(%w+) (%a+)(.*)$")
  if pv == "folds" or pv == "checks" or pv == "calls" or pv == "bets" or pv == "raises" then hs.onPlay(pn, pv, pr) end
  local shn, sht = l:match("^The High Stakes Dealer says, '(%w+) shows (.+)'"); if shn then hs.onShow(shn, sht) end
  local wn, wa = l:match("^The High Stakes Dealer says, '[%a%. ]-(%w+) %a+ the pot of ([%d,]+)")
  if not wn then wn, wa = l:match("^The High Stakes Dealer says, '(%w+) wins the main pot of ([%d,]+)") end
  if not wn then wn, wa = l:match("^The High Stakes Dealer says, '(%w+) wins a side pot of ([%d,]+)") end
  if wn then hs.onPotWon(wn, wa) end
  local on, ov = l:match("^The High Stakes Dealer says, '(%w+) is out of time and (%a+)%.'"); if on then hs.onTimeout(on, ov) end
  local list = l:match("^%[CKMud Info%]: The Friday High Stakes tournament begins with %d+ players: (.+)%.$")
  if list then hs.onTourneyStart(list) end
  local kn, kp = l:match("^%[CKMud Info%]: (%w+) is knocked out of the High Stakes tournament in (%w+) place%.")
  if kn then hs.onKnockout(kn, kp) end
  if l == "You're out of chips and out of the High Stakes tournament." then hs.onOut() end
  local yt = l:match("^Your turn: (.+)$"); if yt then hs.onYourTurn(yt) end
  local tt = l:match("^TOURNEY: Your turn%. (.+)$")
  if tt then
    hs.onTourneyTurn(tt)
    local t = hs.hand.turn
    if t and t.advice and advice[#advice] ~= t.advice then advice[#advice + 1] = t.advice end
  end
  local ten = l:match("^The High Stakes Dealer says, '(%w+), ten seconds%.'"); if ten then hs.onTenSeconds(ten) end
end
for l in io.lines("tests/fixtures/highstakes.log") do feed(l) end

ok(hs.me == "Vorricer", "works out who you are from 'Action is on <you>' before your turn")
ok(LOG:find("Didn't see your cards"), "joined mid-hand without the cards: says so instead of guessing")
local function a(i) return advice[i] and (advice[i].command .. "  (" .. advice[i].why .. ")") or "none" end
print("    turn  AK on AD 10H 9H 6S, checked to you (early limits): " .. a(1))
ok(advice[1] and advice[1].command == "cbet 75m", "pair of aces, checked to you: bet the fixed 75m")
print("    turn  AK facing a raise and a call:                      " .. a(2))
ok(advice[2] and advice[2].command == "ccall", "pair of aces, 75M into 1.5B: call")
print("    river trip aces facing a bet:                             " .. a(3))
ok(advice[3] and advice[3].command == "ccall",
  "trip aces on a three-heart river, after Stryfe raised and Cicada bet: call, don't raise (Stryfe had the full house)")
print("    22 facing Cicada's 9.2B all in:                           " .. a(4))
ok(advice[4] and advice[4].command == "cfold", "22 against an all in: fold")
ok(LOG:find("<red>CFOLD") or LOG:find("<red>FOLD"), "the ten seconds warning repeats the advice in red")
ok(sent[#sent] == "cfold" and LOG:find("Ten seconds left: playing cfold", 1, true), "and plays it")
print("    72o on the button facing the big blind:                   " .. a(5))
ok(advice[5] and advice[5].command == "cfold", "7-2 offsuit: fold")
print("    J8o in the big blind facing a raise:                      " .. a(6))
ok(advice[6] and advice[6].command == "cfold", "J-8 offsuit vs a raise: fold")
ok(#hs.seats == 3 and hs.bb == 200000000 and not hs.early, "table: 3 players, blinds 100M/200M, no limit now")
ok(hs.players.Cicada and hs.players.Cicada.allins == 2 and hs.players.Cicada.shows[1]:find("Two Pair"),
   "remembers Cicada's two all ins and what they showed")
ok(not hs.players.Everyone and #hs.seats == 3, "'Everyone folds' isn't a player")

-- A second tournament: the advice that changed --------------------------------------
local first = #advice
hs.me = nil
local turnAfterTimeout, wonBefore = "unset", hs.stats.won
for l in io.lines("tests/fixtures/highstakes2.log") do
  feed(l)
  if l:find("Vorrac is out of time and folds", 1, true) then turnAfterTimeout = hs.hand.turn end
end

local function adv(i) return advice[first + i] or {} end
ok(adv(1).command == "ccall" and math.abs(adv(1).need - 50 / 300) < 0.01,
  "J2s in the small blind, limped pot: complete for half a bet (needs 17%, shown preflop too)")
ok(adv(4).why:find("mostly the board: a weak pair", 1, true), "66 on a QQ board is called a weak pair, not just Two Pair")
ok(turnAfterTimeout == nil, "out of time: the turn is over, so hs go has nothing stale to send")
ok(adv(11).command == "cfold", "board two pair AA88, Snuggles re-raises the river: fold (he had the full house)")
ok(adv(13).command == "ccall", "hand 19 flop: top pair, Carolina bets once: call")
ok(adv(14).command == "ccall" or adv(14).command == "cfold",   -- 18% vs 17% needed: on the edge either way
  "hand 19 turn: she bet the flop and the turn: call or fold, never raise (" .. adv(14).why .. ")")
ok(adv(14).equity < 0.4, string.format("...because she has top pair or better now: %.0f%%, not the old 83%%", adv(14).equity * 100))
ok(adv(15).command == "cfold", "hand 19: she re-raises: one pair folds instead of raising until all in")
ok(hs.stacks.Snuggles == 10550000000, "the '>' row of the player to act is read too")
ok(hs.stats.won == wonBefore + 1, "hand 5's pot counted as won")
ok(hs.out and hs.stats.finishes == "3rd" and #hs.seats == 2, "knocked out in 3rd: recorded, and off the table")
local before = hs.stats.won
hs.me = "Vorrac"; feed("The High Stakes Dealer says, 'Vorrac wins a side pot of 200,000,000 (One Pair).'")
ok(hs.stats.won == before + 1, "side pots count as won")

-- No limit sizing ---------------------------------------------------------------
local ctx = { hole = C("[AS] [AH]"), board = {}, toCall = 200e6, pot = 300e6, stack = 9e9, bb = 200e6, nOpp = 2,
              minRaise = 400e6, noLimit = true, sims = 500 }
local d = hs.decide(ctx)
ok(d.command == "craise 600m", "AA unopened: raise to 3 big blinds (" .. d.command .. ")")
ctx.toCall, ctx.pot, ctx.minRaise = 600e6, 1e9, 1e9
d = hs.decide(ctx)
ok(d.command == "craise 1.8b", "AA facing a raise: re-raise to 3x (" .. d.command .. ")")
ctx.stack = 1.5e9; d = hs.decide(ctx)
ok(d.command == "craise all", "a re-raise over half the stack becomes all in")
ctx = { hole = C("[KS] [9D]"), board = {}, toCall = 200e6, pot = 300e6, stack = 1.6e9, bb = 200e6, nOpp = 2,
        minRaise = 400e6, noLimit = true, sims = 500 }
d = hs.decide(ctx); ok(d.command == "cfold", "K9o with 8 big blinds: fold (" .. d.why .. ")")
ctx.hole = C("[AS] [4D]"); d = hs.decide(ctx); ok(d.command == "craise all", "A4o with 8 big blinds: all in")

-- hs go sends the advice; nothing is sent otherwise
sent = {}
hs.hand.turn = { toCall = 0, advice = { command = "ccheck", action = "check", why = "test" } }
hs.command("go"); ok(sent[1] == "ccheck" and #sent == 1, "hs go sends the suggested move")
hs.onTenSeconds("Vorrac"); ok(#sent == 1, "already moved with hs go: the warning doesn't send it again")
hs.command("auto", "off")
hs.hand.turn = { toCall = 0, advice = { command = "ccheck", action = "check", why = "test" } }
hs.onTenSeconds("Vorrac"); ok(#sent == 1, "hs auto off: the warning only shows the advice")
hs.command("auto", "on"); hs.onTenSeconds("Vorrac"); ok(#sent == 2 and sent[2] == "ccheck", "hs auto on: plays it")
hs.onTenSeconds("Someone"); ok(#sent == 2, "someone else's warning: nothing")
hs.command("help"); hs.command("players"); hs.command("status"); hs.command("bogus")
print("\nhs: ALL PASSED")
