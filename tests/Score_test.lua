-- sc: Score. Run from the repo root: lua tests/Score_test.lua
local out, saved, gagged, clock = "", nil, 0, 1000000
function cecho(s) out = out .. s end
function echo(s) out = out .. s end
function getEpoch() return clock end
function getMudletHomeDir() return "/nonexistent-score-test" end
function deleteLine() gagged = gagged + 1 end
table.save = function(_, t) saved = t end
-- the 2.x switches database, to check they're brought over
io.exists = function(f) return f:find("Database_score.db", 1, true) ~= nil end
db = { create = function() return { Toggles = "T" } end,
       fetch = function() return { { name = "score.prompt_gravity", value = 0 }, { name = "score.other", value = 0 } } end }

MSDP = { Player = { Pl = 900000000, MaxPl = 1000000000, BasePl = 600000000, Ki = 5000, MaxKi = 10000,
                    GK = 400, MaxGK = 500, Damroll = 100, Hitroll = 120, Zenni = 130000000, MaxGravity = 20,
                    Stats = { STR = 300, INT = 400, WIS = 500, SPD = 200, CON = 250 },
                    BaseStats = { STR = 290, INT = 380, WIS = 480, SPD = 150, CON = 240 } },
         Room = { Gravity = 5 } }
local P = MSDP.Player

local function ok(c, what) assert(c, what); print("OK  " .. what) end
local function say(l) sc.line(l) end

dofile("packages/Score/src/Score.lua")
ok(sc.on.gravity == false and sc.on.extras and sc.on.regen and saved.on.gravity == false,
  "brings the 2.x switches over (prompt gravity was off)")
sc.command("gravity", "on")
ok(sc.on.gravity and saved.on.gravity, "sc gravity on (saved)")

-- ---- numbers
ok(sc.itemTier(600000000) == 6 and sc.itemTier(999999) == 0 and sc.itemTier(9000000000) == 10, "item tiers")
local nt, need = sc.nextTier(600000000)
ok(nt == 7 and need == 900000000, "next tier 7 needs 900M more")
ok(sc.nextTier(9000000000) == nil, "no next tier at the top")
local stat, value = sc.lowestStat()
ok(stat == "SPD" and value == 150, "lowest base stat")
P.BaseStats.CON = 11
ok(sc.lowestStat() == "SPD", "CON never counts")
ok(sc.trainingGravity() == 19, "training gravity capped at max - 1")
P.MaxPl = 500000; ok(sc.trainingGravity() == 6, "a low PL is limited by the formula"); P.MaxPl = 1000000000
ok(sc.gauntletRuns() == 5, "gauntlet runs from zenni")
ok(sc.kiDam() > 0 and sc.phyDam() > 0 and sc.kiDam(true) > sc.kiDam() and sc.heal() > 0, "damage and heal")
ok(sc.kiDam() == math.floor(400 * 1.8 * 5000 + 500 / 5 * 5000 + 100 * 500 + 120 * 500 + 2000000), "ki damage formula")
ok(sc.format(1234567) == "1,234,567" and select("#", sc.format(1)) == 1, "number format")

-- ---- the block
out = ""; sc.command("show")
ok(out:find("PHY DAM", 1, true) and out:find("KI DAM(U)", 1, true) and out:find("HEAL", 1, true), "damage and heal lines")
ok(out:find("ITEM TIER", 1, true) and out:find("900,000,000 more base PL for tier 7", 1, true), "tier line")
ok(out:find("TRAIN NEXT", 1, true) and out:find("SPD (150)", 1, true), "training hint")
ok(out:find("19x to train  (max 20x)", 1, true) and out:find("GAUNTLET RUNS", 1, true), "gravity and gauntlet")
P.BasePl = 9000000000; out = ""; sc.show(); ok(out:find("10  (max)", 1, true), "top tier shows (max)")
P.BasePl = nil; msdp = { BASE_PL = "1,001,713,664" }
local nt2, need2 = sc.nextTier()
ok(sc.itemTier() == 6 and nt2 == 7 and need2 == 498286336, "base PL from Mudlet's msdp table when MSDP has none")
msdp = nil; out = ""; sc.show()
ok(out:find("no base PL yet", 1, true), "says why the tier is unknown")
P.BasePl = 600000000
P.Stats.INT = nil; out = ""; sc.show()
ok(out:find("Waiting on MSDP", 1, true) and not out:find("PHY DAM", 1, true), "waits for MSDP data")
P.Stats.INT = 400
local keep = MSDP; MSDP = nil; out = ""; sc.show()
ok(out:find("needs the MSDP package", 1, true), "says when MSDP is missing")
MSDP = keep

-- ---- on the score sheet
out = ""; say("Green Orbs: 12")
ok(out:find("ITEM TIER", 1, true), "printed at Green Orbs")
out = ""; say("See 'Status', 'Train', and 'Traits' for more information.")
ok(out == "", "only once per sheet")
clock = clock + 5; out = ""; say("See 'Status', 'Train', and 'Traits' for more information.")
ok(out:find("ITEM TIER", 1, true), "or at the closing line, on a later score")
sc.command("extras", "off"); clock = clock + 5; out = ""; say("Green Orbs: 12")
ok(out == "" and saved.on.extras == false, "sc extras off")
sc.command("extras", "on")

gagged, out = 0, ""; say("Ki:  50%  KI REGEN: 3%")
ok(gagged == 1 and out:find("5,000", 1, true) and out:find("300", 1, true) and P.KiRegen == 300, "Ki line in real numbers")
gagged, out = 0, ""; say("GodKi:  80%  GODKI REGEN: 10%")
ok(gagged == 1 and P.GKRegen == 50 and out:find("GODKI REGEN", 1, true), "GodKi line")
gagged, out = 0, ""; say("BioMass:  50%  BM REGEN: 4%")
ok(gagged == 1 and P.KiRegen == 400 and out:find("BM REGEN", 1, true), "BioMass line")
gagged, out = 0, ""; say("Heat:  20%  Dissipation: 5%")
ok(gagged == 1 and out:find("5,000", 1, true) and out:find("500", 1, true), "Heat line (used ki) and dissipation")
P.MaxKi = nil; gagged = 0; say("Ki:  50%  KI REGEN: 3%")
ok(gagged == 0, "left alone until MSDP has max ki"); P.MaxKi = 10000
sc.command("regen", "off"); gagged = 0; say("Ki:  50%  KI REGEN: 3%")
ok(gagged == 0, "sc regen off leaves the lines alone")
sc.command("regen", "on")

-- ---- gravity on the prompt
out = ""; say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(out:find("<red>5<white>/<red>20x G", 1, true), "prompt shows gravity, red below max")
MSDP.Room.Gravity = 20; out = ""; say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(out:find("<green>20", 1, true), "green at max")
MSDP.Room.Gravity = nil; out = ""; say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(out == "", "nothing while gravity is unknown")
MSDP.Room.Gravity = 5; sc.command("gravity", "off"); out = ""; say("[Pl: 4,320 | Ki: 100%] [HT]")
ok(out == "", "sc gravity off")

out = ""; sc.command()
ok(out:find("sc show", 1, true) and out:find("gravity off", 1, true), "help with the switches")

-- a settings file wins over the old database
table.load = function(_, t) t.on = { extras = false } end
local realOpen = io.open
io.open = function(f, ...) if f:find("nonexistent%-score%-test") then return {} end return realOpen(f, ...) end
sc = nil
dofile("packages/Score/src/Score.lua")
io.open = realOpen
ok(sc.on.extras == false and sc.on.gravity == true, "with a settings file the old database isn't read")

print("All Score tests passed")
