-- bj: card parsing, basic strategy, and the table flow from real game output.
-- Run from the repo root: lua tests/Blackjack_test.lua
local sent, timers = {}, {}
msdp = {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(_, f) timers[#timers + 1] = f end
local function flush() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
local function expect(want)
  flush()
  local got = table.concat(sent, " | "); sent = {}
  assert(got == want, "\n got: " .. got .. "\nwant: " .. want)
  print("OK  " .. (want == "" and "(nothing)" or want))
end

dofile("packages/Blackjack/src/Blackjack.lua")

-- Cards and totals ------------------------------------------------------------
assert(table.concat(bj.parseCards("[ A] [ 4] (15)"), ",") == "A,4")
assert(table.concat(bj.parseCards("[ A] [XX]"), ",") == "A")                    -- hidden card skipped
assert(table.concat(bj.parseCards("[ 4] [ 9] (13) [STAND]"), ",") == "4,9")      -- tags skipped
assert(table.concat(bj.parseCards("[10] [ K] (20)"), ",") == "10,K")
local t, soft = bj.total({ "A", "4" }); assert(t == 15 and soft)
t, soft = bj.total({ "A", "9", "5" }); assert(t == 15 and not soft)
t, soft = bj.total({ "K", "10" }); assert(t == 20 and not soft)
print("OK  card parsing and totals")

-- Basic strategy (dealer stands on soft 17): { cards, dealer upcard, can double, expected }
local cases = {
  { { "10", "6" }, "10", true, "hit" },    { { "10", "6" }, "6", true, "stand" },
  { { "10", "2" }, "3", true, "hit" },     { { "10", "2" }, "4", true, "stand" },
  { { "6", "5" }, "10", true, "double" },  { { "6", "5" }, "A", true, "hit" },
  { { "5", "4" }, "2", true, "hit" },      { { "5", "4" }, "3", true, "double" },
  { { "A", "7" }, "2", true, "stand" },    { { "A", "7" }, "9", true, "hit" },
  { { "A", "7" }, "5", true, "double" },   { { "A", "7" }, "5", false, "stand" },
  { { "A", "6" }, "4", false, "hit" },     { { "A", "8" }, "6", true, "stand" },
  { { "K", "Q" }, "A", true, "stand" },    { { "A", "A", "9" }, "10", false, "stand" },
  { { "A", "4" }, "6", true, "double" },   { { "4", "9" }, "A", true, "hit" },
}
for _, c in ipairs(cases) do
  local got = bj.decide(c[1], c[2], c[3])
  assert(got == c[4], table.concat(c[1], ",") .. " vs " .. c[2] .. ": got " .. got .. ", want " .. c[4])
end
print("OK  strategy (" .. #cases .. " cases)")

-- Joining ---------------------------------------------------------------------
bj.join(); bj.welcomed("Vorrac"); assert(not bj.active)     -- cjoin without an offered seat: bot stays off
expect("cjoin")
bj.invite(); bj.join(); bj.welcomed("Vorricer"); assert(bj.active and bj.me == "Vorricer")
expect("cjoin")
bj.welcomed("Bob"); assert(bj.me == "Vorricer")               -- someone else joining doesn't take over

-- A round with a long name (padded table) and repeated option lines ---------------------------
local OPTIONS = "BLACKJACK: Hit(chit), Double Down(cdouble) or Stand(cstand)?"
bj.placeBet(); expect("blackjack bet")
bj.showHand("Dealer", "[ A] [XX]"); bj.showHand("Vorricer", "[ 4] [ 9] (13)")
bj.turn("Vorricer"); bj.options(OPTIONS); expect("chit")          -- hard 13 vs A
bj.options(OPTIONS); bj.options(OPTIONS); expect("")               -- repeated prompt: no extra move
bj.showHand("Vorricer", "[ 4] [ 9] [ 6] (19)"); bj.turn("Vorricer")
bj.options("BLACKJACK: Hit(chit) or Stand(cstand)?"); expect("cstand")
bj.nudge("Vorricer"); bj.options(OPTIONS); expect("")              -- nudge right after a move is ignored
bj.lastMoveAt = os.time() - 10
bj.nudge("Vorricer"); bj.options(OPTIONS); expect("cstand")        -- a stale nudge means the move was lost

-- Other players' turns are ignored
bj.placeBet(); expect("blackjack bet")
bj.showHand("Dealer", "[ 5] [XX]"); bj.showHand("Bob", "[ 2] [ 3] (5)"); bj.showHand("Vorricer", "[10] [ 2] (12)")
bj.turn("Bob"); bj.options(OPTIONS); expect("")
bj.turn("Vorricer"); bj.options(OPTIONS); expect("cstand")          -- 12 vs 5

-- Results ---------------------------------------------------------------------
bj.roundEnd(); bj.won("20,000,000"); bj.luckyTails("100"); bj.xpGained("120,000")
bj.roundEnd(); bj.lost("20,000,000"); bj.roundEnd()
local s = bj.stats
assert(s.rounds == 3 and s.wins == 1 and s.losses == 1 and s.zenniWon == 20000000 and s.zenniLost == 20000000)
assert(s.tails == 100 and s.xp == 120000)
assert(bj.fmt(-1234567) == "-1,234,567" and bj.fmt(0) == "0")
bj.stop(); bj.won("5"); bj.roundEnd(); assert(bj.stats.rounds == 3)   -- nothing counted while off
print("OK  stats")

bj.command("help"); bj.command("status")
print("\nbj: ALL PASSED")
