-- casino: the shared core with every game loaded together, as the package installs them.
-- Run from the repo root: lua tests/Casino_test.lua
local sent = {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer() return 1 end
function killTimer() end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end
local function took() local s = table.concat(sent, " | "); sent = {}; return s end

local function loadAll()
  for _, f in ipairs({ "Core", "Blackjack", "VideoPoker", "HighStakes", "Slots" }) do
    dofile("packages/Casino/src/" .. f .. ".lua")
  end
end
loadAll()

-- Helpers -----------------------------------------------------------------------
ok(casino.num("25,000,000") == 25000000 and casino.fmt(-1234567) == "-1,234,567", "num and fmt")
ok(casino.signed(5) == "+5" and casino.signed(-5) == "-5", "signed")
ok(casino.parseAmount("1.5b") == 1500000000 and casino.parseAmount("250k") == 250000 and casino.parseAmount("x") == nil,
  "parseAmount")
ok(vp.parseAmount == casino.parseAmount and bj.fmt == casino.fmt, "games share the core helpers")

-- Registry ----------------------------------------------------------------------
local keys = {}
for _, g in ipairs(casino.games) do keys[#keys + 1] = g.key end
ok(table.concat(keys, ",") == "bj,vp,hs,sl", "every game registers, in load order")
loadAll()
ok(#casino.games == 4, "reloading the scripts doesn't register a game twice")

-- cjoin -------------------------------------------------------------------------
casino.join()
ok(took() == "cjoin" and not bj.joining, "cjoin with no blackjack seat offered: sent, blackjack stays out")
bj.invite(); casino.join()
ok(took() == "cjoin" and bj.joining, "cjoin after the blackjack dealer's offer arms blackjack")
bj.welcomed("Vorricer")
ok(bj.active, "blackjack bot on after the welcome")

-- Rewards go to the game being played --------------------------------------------
casino.luckyTails("100"); casino.xpGained("120,000", "intelligence")
ok(bj.stats.tails == 100 and bj.stats.xp == 120000 and vp.stats.tails == 0, "rewards credit blackjack while it plays")
ok(casino.stats.tails == 100 and casino.stats.xp.intelligence == 120000, "and count casino-wide")
bj.stop()
casino.luckyTails("50"); casino.xpGained("10", "strength")
ok(casino.stats.tails == 100 and not casino.stats.xp.strength and bj.stats.tails == 100,
  "no bot playing: rewards from elsewhere aren't counted")
vp.active = true
casino.luckyTails("1,000"); casino.xpGained("7", "STR")
ok(vp.stats.tails == 1000 and vp.stats.xp == 7 and casino.stats.xp.str == 7, "rewards credit video poker while it plays")
vp.active = false

-- casino command ------------------------------------------------------------------
LOG = ""; casino.command()
ok(LOG:find("bj", 1, true) and LOG:find("Video Poker", 1, true) and LOG:find("High Stakes", 1, true), "casino lists the games")
LOG = ""; casino.command("status")
ok(LOG:find("Blackjack", 1, true) and LOG:find("0 rounds", 1, true) and LOG:find("Lucky Tails: 1,100", 1, true),
  "casino status shows each game and the totals")
bj.active, vp.active, sl.active = true, true, true
LOG = ""; casino.command("stop")
ok(not bj.active and not vp.active and not sl.active, "casino stop stops every bot")
casino.command("reset")
ok(casino.stats.tails == 0 and next(casino.stats.xp) == nil, "casino reset clears the totals")
LOG = ""; casino.command("nonsense")
ok(LOG:find("Unknown command", 1, true), "unknown commands are reported")

print("casino: ALL PASSED")
