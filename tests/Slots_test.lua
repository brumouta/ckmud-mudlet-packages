-- sl: payout scoring, and the pull loop replayed against 15 real pulls from the game.
-- Run from the repo root: lua tests/Slots_test.lua
local now, timers, nextId, sent, deleted = 0, {}, 0, {}, 0
function cecho(s) LOG = (LOG or "") .. s end
function deleteLine() deleted = deleted + 1 end
function alert() ALERTED = true end
function tempTimer(d, f) nextId = nextId + 1; timers[nextId] = { at = now + d, f = f }; return nextId end
function killTimer(i) timers[i] = nil end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end

-- The real pulls, one block each
local PULLS, block = {}, nil
for l in io.lines("tests/fixtures/slots.log") do
  if l:find("^You put") then block = {}; PULLS[#PULLS + 1] = block end
  if block and l ~= "" then block[#block + 1] = l end
end
assert(#PULLS == 15)

-- Lines go through the same triggers as package.json
local function feed(l)
  line = l
  local z = l:match("^You put ([%d,]+) zenni in the slot machine%.") if z then sl.onBet(z) end
  local a, b, c = l:match("^%s*%[%s*|(...)|%s*|(...)|%s*|(...)|%s*%]%s*$") if a then sl.onReels(a, b, c) end
  local w = l:match("^You won ([%d,]+) zenni!$") if w then sl.onResult(w) end
  if l:match("^You lost your ([%d,]+) zenni!$") then sl.onResult("0") end
  if l == "Slot Machine Results:" or l:match("^o%-+o$") and #l >= 22 and #l <= 32 or l == "See payouts by typing 'payout'." then sl.gag() end
  local t = l:match("^You earn ([%d,]+) Lucky Tails") if t then casino.luckyTails(t) end
  local x, stat = l:match("^You have gained ([%d,]+) (%w+) XP") if x then casino.xpGained(x, stat) end
end

-- The machine answers each `pull` with the next real pull (after a short spin)
local machine = { next = 1, answers = true }
function send(c)
  sent[#sent + 1] = c
  if c:match("^pull %d$") and machine.answers then
    local p = PULLS[(machine.next - 1) % #PULLS + 1]; machine.next = machine.next + 1
    tempTimer(0.5, function() for _, l in ipairs(p) do feed(l) end end)
  end
end
local function wait(secs)
  local target = now + secs
  while true do
    local best, id
    for i, t in pairs(timers) do if t.at <= target and (not best or t.at < best.at) then best, id = t, i end end
    if not best then break end
    timers[id] = nil; now = best.at; best.f()
  end
  now = target
end
local function count(cmd) local n = 0; for _, c in ipairs(sent) do if c == cmd then n = n + 1 end end; return n end
local function fresh() sl.stats = nil; sl.active = false; dofile("packages/Casino/src/Slots.lua"); sent = {}; LOG = ""; machine.next = 1; deleted = 0 end

dofile("packages/Casino/src/Core.lua")
dofile("packages/Casino/src/Slots.lua")

-- Scoring, against the payout table ----------------------------------------------------
local function grid(s) local r = {}; for row in s:gmatch("[^/]+") do local t = {}; for c in row:gmatch("%S+") do t[#t + 1] = c end; r[#r + 1] = t end; return r end
local P = 2500000
ok(sl.evaluate(grid("ZZZ X C / BBB C o / C X BB"), 5, P) == 25000000, "full Cherry diagonal at 5 lines: 2x * 2.5m * 5 = 25m")
ok(sl.evaluate(grid("ZZZ X C / BBB C o / C X BB"), 4, P) == 0, "...which isn't played at 4 lines")
ok(sl.evaluate(grid("Z Z X / Z BB C / o BBB C"), 5, P) == 15000000, "first two reels Z on the top row: 10% of 12x = 15m")
ok(sl.evaluate(grid("Z Z X / Z BB C / o BBB C"), 1, P) == 0, "...but only the middle row counts at 1 line")
ok(sl.evaluate(grid("X X X / C C C / o o o"), 1, P) == 5000000, "full Cherry middle row at 1 line: 5m")
ok(sl.evaluate(grid("C C C / C C C / o o o"), 2, P) == (5000000 * 2 * 2) * 10, "middle and top rows of the same symbol: x10")
ok(sl.evaluate(grid("C C C / C C C / C C C"), 5, P) == (5000000 * 5 * 5) * 25, "every row the same symbol: x25")
local pay, hits = sl.evaluate(grid("(*) (*) (*) / X C o / C X BB"), 2, P)
ok(pay == 250 * P * 2 and hits[1].symbol == "(*)" and hits[1].full, "Dragonball top row at 2 lines: 250x")

-- The 15 real pulls ----------------------------------------------------------------------
sl.command("start")
wait(200)
local s = sl.stats
ok(s.pulls >= 15, "keeps pulling, one pull per result")
sl.command("stop"); wait(5)
s = sl.stats
fresh(); sl.maxPulls = 15
sl.command("start"); wait(200)
s = sl.stats
ok(count("pull 5") == 15 and not sl.active, "15 pulls, then stops at the pull limit")
ok(s.mismatches == 0, "the scoring agrees with every payout the machine made")
ok(s.bet == 187500000 and s.won == 60000000, "in 187.5m, out 60m")
ok(s.wins == 5 and s.best == 25000000 and s.full == 1, "5 paying pulls, best 25m, one full line")
ok(s.tails == 10 and s.xp == 1800000, "Lucky Tails and STR XP from the VIP win")
ok(deleted == 15 * 9, "quiet: the machine's 9 lines a pull are hidden")
ok(LOG:find("won 25,000,000 (+12,500,000)  Cherry diagonal", 1, true), "one summary line a pull, with the line that paid")
ok(LOG:find("2x Z top", 1, true), "two-reel wins are named too")

-- Stop loss, target, stop after the pull ---------------------------------------------------
fresh(); sl.command("stoploss", "60m")
sl.command("start"); wait(200)
ok(count("pull 5") == 5 and LOG:find("stop loss reached (-60,000,000)", 1, true), "stop loss 60m: 4 losses after the 2.5m win, then stops")
sl.stopLoss = 0
fresh(); machine.next = 10; sl.command("target", "10m")
sl.command("start"); wait(200)
ok(count("pull 5") == 1 and LOG:find("target reached (+12,500,000)", 1, true), "target 10m: stops after the 25m win")
sl.target = 0
fresh(); sl.command("start"); wait(0.6)
ok(sl.state == "idle" or sl.state == "spinning", "first pull answered")
sl.command("stop"); wait(10)
ok(count("pull 5") == 1 and not sl.active, "sl stop between pulls stops")
fresh(); sl.command("start")
tempTimer(0.2, function() sl.command("stop") end)   -- while the reels spin
wait(10)
ok(count("pull 5") == 1 and not sl.active and sl.stats.pulls == 1 and sl.stats.won == 2500000,
  "sl stop while spinning: finishes that pull, then stops")

-- No machine ------------------------------------------------------------------------------------
fresh(); machine.answers = false
sl.command("start"); wait(60)
ok(count("pull 5") == 3 and not sl.active and LOG:find("didn't answer", 1, true), "no answer: retries twice, then stops")
machine.answers = true

-- Lines, quiet, help -----------------------------------------------------------------------------
fresh(); sl.command("lines", "3"); sl.command("pulls", "1"); sl.command("quiet", "off")
sl.command("start"); wait(10)
ok(count("pull 3") == 1 and deleted == 0, "3 lines, reels shown when quiet is off")
sl.command("lines", "9"); ok(sl.lines == 3, "lines outside 1-5 are refused")
LOG = ""; casino.command("status")
ok(LOG:find("Slots", 1, true) and LOG:find("1 pulls", 1, true), "shows in casino status")
LOG = ""; sl.command("bogus")
ok(LOG:find("Unknown command", 1, true), "unknown commands are reported")

-- Not playing: other games' lines and pulls by hand are left alone --------------------------------------
fresh(); feed("You put 12,500,000 zenni in the slot machine."); feed("You won 2,500,000 zenni!")
ok(sl.stats.pulls == 0 and deleted == 0, "pulls by hand with the bot off aren't counted or hidden")

print("sl: ALL PASSED")
