-- sl: the pull loop, zenni tracking from MSDP and every stop condition.
-- Run from the repo root: lua tests/Slots_test.lua
local now, timers, nextId, sent = 0, {}, 0, {}
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) nextId = nextId + 1; timers[nextId] = { at = now + d, f = f }; return nextId end
function killTimer(i) timers[i] = nil end
local function ok(cond, what) assert(cond, what); print("OK  " .. what) end
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

-- A slot machine: each line costs 1m and a pull pays the next amount in `pays`
MSDP = { Player = { Zenni = 100000000 } }
local pays, atMachine = {}, true
function send(c)
  sent[#sent + 1] = c
  local lines = tonumber(c:match("^pull (%d)$"))
  if lines and MSDP and atMachine and MSDP.Player.Zenni >= lines * 1000000 then
    MSDP.Player.Zenni = MSDP.Player.Zenni - lines * 1000000 + (table.remove(pays, 1) or 0)
  end
end
local function count(cmd) local n = 0; for _, c in ipairs(sent) do if c == cmd then n = n + 1 end end; return n end
local function fresh(zenni) sl.stats = nil; dofile("packages/Casino/src/Slots.lua"); sent = {}; MSDP.Player.Zenni = zenni; LOG = "" end

dofile("packages/Casino/src/Core.lua")
dofile("packages/Casino/src/Slots.lua")

-- Pull limit, and the score from zenni -----------------------------------------------
sl.command("pulls", "4")
pays = { 0, 12000000, 0, 0 }
sl.command("start")
ok(sent[1] == "pull 5", "pulls 5 lines straight away")
wait(60)
ok(count("pull 5") == 4 and not sl.active, "stops after the pull limit (4 pulls)")
ok(sl.stats.wins == 1 and sl.stats.best == 7000000, "one winning pull, best win +7m (12m paid on a 5m pull)")
ok(sl.stats.zenni - sl.stats.startZenni == -8000000, "zenni net -8m (4 x 5m in, 12m back)")
ok(LOG:find("Stopped: played 4 pulls", 1, true), "says why it stopped")

-- Lines and delay ----------------------------------------------------------------------
fresh(100000000); sl.maxPulls = 3
sl.command("lines", "2"); sl.command("delay", "10")
sl.command("start"); wait(15)
ok(count("pull 2") == 2, "2 lines, 10s apart: two pulls in 15s")
sl.command("stop"); wait(60)
ok(count("pull 2") == 2 and not sl.active, "sl stop stops pulling")
sl.command("lines", "9"); ok(sl.lines == 2, "lines outside 1-5 are refused")
sl.lines, sl.delay, sl.maxPulls = 5, 4, 0

-- Stop loss, target, keep -------------------------------------------------------------
fresh(100000000); sl.command("stoploss", "12m")
sl.command("start"); wait(120)
ok(count("pull 5") == 3 and sl.stats.zenni == 85000000, "stop loss 12m: stops once down 15m, after 3 pulls")
sl.stopLoss = 0

fresh(100000000); sl.command("target", "20m"); pays = { 0, 30000000 }
sl.command("start"); wait(120)
ok(count("pull 5") == 2 and LOG:find("target reached (+20,000,000)", 1, true), "target 20m: stops after the 30m win")
sl.target = 0

fresh(100000000); sl.command("keep", "90m")
sl.command("start"); wait(120)
ok(count("pull 5") == 3 and sl.stats.zenni == 85000000, "keep 90m: stops once zenni drops below 90m")
sl.keep = 0

-- Not at a machine / out of zenni -------------------------------------------------------
fresh(100000000); atMachine = false
sl.command("start"); wait(120)
ok(count("pull 5") == 3 and not sl.active and LOG:find("didn't change for 3 pulls", 1, true),
  "zenni never changes: stops after 3 pulls")
atMachine = true

fresh(7000000)
sl.command("start"); wait(120)
ok(count("pull 5") == 4 and not sl.active, "out of zenni (can't pay a pull): stops once pulls stop costing")

-- Without MSDP ----------------------------------------------------------------------------
local saved = MSDP; MSDP = nil
local function fresh2() sl.stats = nil; dofile("packages/Casino/src/Slots.lua"); sent = {}; LOG = "" end
fresh2(); sl.maxPulls = 5
sl.command("start"); wait(120)
ok(count("pull 5") == 5 and LOG:find("No zenni from MSDP", 1, true), "no MSDP: warns, and the pull limit still works")
sl.maxPulls = 0; MSDP = saved

-- Rewards through the casino core -----------------------------------------------------------
fresh(100000000); sl.command("start")
casino.luckyTails("100"); casino.xpGained("50,000", "STR")
ok(sl.stats.tails == 100 and sl.stats.xp == 50000, "Lucky Tails and STR XP are credited to slots while it pulls")
sl.command("stop")
LOG = ""; casino.command("status")
ok(LOG:find("Slots", 1, true) and LOG:find("1 pulls", 1, true), "shows in casino status")
LOG = ""; sl.command("bogus")
ok(LOG:find("Unknown command", 1, true), "unknown commands are reported")

print("sl: ALL PASSED")
