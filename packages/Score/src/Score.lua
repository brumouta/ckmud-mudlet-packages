-- sc: a richer score sheet. Rewrites the Ki/GodKi/BioMass/Heat percentage lines into real
-- numbers, appends damage at every boost level, item tier, heal, training hints and gauntlet
-- runs, and adds the room's gravity against your max to the prompt.
-- Every number comes from the MSDP package (base PL too: it reads it from `score`).
sc = sc or {}
local S = sc

local function info(color, msg) cecho("\n<" .. color .. ">[sc] <white>" .. msg .. "\n") end

-- ---------------------------------------------------------------- settings (saved)
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/score.lua"
S.SWITCHES = {
  { "extras",  "The block added to the score sheet" },
  { "regen",   "Ki/GodKi/BioMass/Heat lines in real numbers instead of %" },
  { "gravity", "Gravity against your max on the prompt" },
}
S.on = S.on or { extras = true, regen = true, gravity = true }

function S.save()
  if type(table.save) == "function" then pcall(table.save, FILE, { on = S.on }) end
end

local function take(t)
  for _, sw in ipairs(S.SWITCHES) do
    if type(t[sw[1]]) == "boolean" then S.on[sw[1]] = t[sw[1]] end
  end
end

-- Score 2.x kept its switches in Mudlet's "Score" database (SC feature score.<name> on|off):
-- bring them over once, the first time 3.x loads without a settings file.
local OLD_NAMES = { ["score.extras"] = "extras", ["score.regen"] = "regen", ["score.prompt_gravity"] = "gravity" }
local function migrate()
  if type(db) ~= "table" or type(db.create) ~= "function" then return end
  local dbFile = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/Database_score.db"
  local exists = type(io.exists) == "function" and io.exists(dbFile)
  if not exists then local f = io.open(dbFile); if f then f:close(); exists = true end end
  if not exists then return end
  local ok, schema = pcall(db.create, db, "Score", {
    Toggles = { name = "", value = 0, _unique = { "name" }, _violations = "REPLACE" },
    Constants = { name = "", value = "", _unique = { "name" }, _violations = "REPLACE" },
  })
  if not ok or not schema then return end
  local okT, rows = pcall(db.fetch, db, schema.Toggles)
  local t = {}
  for _, r in ipairs(okT and rows or {}) do
    local name = OLD_NAMES[r.name]
    if name then t[name] = r.value == 1 end
  end
  take(t)
  S.save()
end

local function load()
  if type(table.load) == "function" and io.open(FILE) then
    local t = {}
    pcall(table.load, FILE, t)
    if type(t.on) == "table" then take(t.on) end
  else
    migrate()
  end
end
load()

-- ---------------------------------------------------------------- numbers
local function M() return rawget(_G, "MSDP") end
local function player() local m = M(); return m and m.Player or {} end
local function room() local m = M(); return m and m.Room or {} end

function S.format(i)
  return (tostring(i):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", ""))
end
local fmt = S.format

local function dam(stat1, stat2, supreme, boosted, ultimate)
  local P = player()
  local supremeMulti = supreme and 7500 or 5000
  if ultimate then supremeMulti = supremeMulti * 2 end
  local boostMulti = (boosted or supreme) and 750 or 500
  return math.floor((stat1 * 1.8) * supremeMulti + (stat2 / 5) * supremeMulti
    + (P.Damroll or 0) * boostMulti + (P.Hitroll or 0) * boostMulti + math.min(P.MaxPl / 200, 2000000))
end

function S.kiDam(supreme, boosted, ultimate)
  local st = player().Stats
  return dam(st.INT, st.WIS, supreme, boosted, ultimate)
end

function S.phyDam(supreme, boosted, ultimate)
  local st = player().Stats
  return dam(st.STR, st.SPD, supreme, boosted, ultimate)
end

function S.heal()
  local P = player()
  return P.Stats.INT * 5000 + P.Stats.WIS * 25000 + P.MaxPl / 100
end

-- Base PL needed for each item tier, ascending
local TIERS = {
  { 1000000, 1 }, { 25000000, 2 }, { 75000000, 3 }, { 125000000, 4 }, { 250000000, 5 },
  { 500000000, 6 }, { 1500000000, 7 }, { 3000000000, 8 }, { 5000000000, 9 }, { 8000000000, 10 },
}
local GAUNTLET_COST = 25000000   -- zenni for one gauntlet run

-- Base PL from the MSDP package, or straight from Mudlet's msdp table if the server sends it
function S.basePl()
  local n = player().BasePl
  if n then return n end
  local raw = type(rawget(_G, "msdp")) == "table" and msdp.BASE_PL or nil
  return raw and tonumber((tostring(raw):gsub(",", ""))) or nil
end

function S.itemTier(basePl)
  basePl = basePl or S.basePl()
  if not basePl then return nil end
  local tier = 0
  for _, row in ipairs(TIERS) do if basePl >= row[1] then tier = row[2] end end
  return tier
end

-- the next tier and how much more base PL it needs
function S.nextTier(basePl)
  basePl = basePl or S.basePl()
  if not basePl then return nil end
  for _, row in ipairs(TIERS) do
    if basePl < row[1] then return row[2], row[1] - basePl end
  end
  return nil   -- already at the top
end

-- The stats worth training: MSDP also reports CON, but the game doesn't use it.
local TRAINABLE = { "STR", "SPD", "WIS", "INT" }
function S.lowestStat()
  local base = player().BaseStats or {}
  local stat, lowest
  for _, id in ipairs(TRAINABLE) do
    local v = base[id]
    if v and (lowest == nil or v < lowest) then stat, lowest = id, v end
  end
  return stat, lowest
end

-- gravity that still trains efficiently, capped just under the max
function S.trainingGravity()
  local P = player()
  local maxPl = P.MaxPl or P.Pl
  if not P.MaxGravity or not maxPl then return nil end
  return math.max(math.min(math.floor((1 / 5000) * 0.06 * maxPl), P.MaxGravity - 1), 1)
end

function S.gauntletRuns()
  local z = player().Zenni
  return z and math.floor(z / GAUNTLET_COST) or nil
end

-- ---------------------------------------------------------------- the block
local function row(label, value, label2, value2)
  if label2 then
    cecho(string.format("<dim_gray>%-14s<white>: <yellow>%-20s<dim_gray>%-12s<white>: <yellow>%s\n",
      label, value, label2, value2))
  else
    cecho(string.format("<dim_gray>%-14s<white>: <yellow>%s\n", label, value))
  end
end

function S.show()
  local P = player()
  if not P.Stats or P.Stats.INT == nil or P.MaxPl == nil then
    if not M() then return info("red", "Score needs the MSDP package for your stats.") end
    return info("yellow", "Waiting on MSDP data, try again in a moment.")
  end
  echo("\n")
  row("PHY DAM", fmt(S.phyDam()), "KI DAM", fmt(S.kiDam()))
  row("PHY DAM(B)", fmt(S.phyDam(false, true)), "KI DAM(B)", fmt(S.kiDam(false, true)))
  row("PHY DAM(S)", fmt(S.phyDam(true)), "KI DAM(S)", fmt(S.kiDam(true)))
  row("PHY DAM(U)", fmt(S.phyDam(true, true, true)), "KI DAM(U)", fmt(S.kiDam(true, true, true)))
  row("HEAL", fmt(math.floor(S.heal())))
  local tier = S.itemTier()
  if tier then
    local nextTier, needed = S.nextTier()
    if nextTier then
      row("ITEM TIER", tier .. "  (need " .. fmt(needed) .. " more base PL for tier " .. nextTier .. ")")
    else
      row("ITEM TIER", tier .. "  (max)")
    end
  else
    row("ITEM TIER", "unknown - no base PL yet (run `score` once more)")
  end
  local stat, value = S.lowestStat()
  if stat then row("TRAIN NEXT", stat .. " (" .. fmt(value) .. ")") end
  local grav = S.trainingGravity()
  if grav then row("GRAVITY", grav .. "x to train  (max " .. P.MaxGravity .. "x)") end
  local runs = S.gauntletRuns()
  if runs then row("GAUNTLET RUNS", fmt(runs)) end
end

-- Both anchors ("Green Orbs:" and the closing line) only appear in a score, so whichever comes
-- first prints and the other falls inside the 2 s window.
function S.showOnce()
  local t = getEpoch()
  if S.lastShown and t - S.lastShown < 2 then return end
  S.lastShown = t
  if S.on.extras then S.show() end
end

-- ---------------------------------------------------------------- score lines and the prompt
local function gag()
  local f = rawget(_G, "deleteLine") or rawget(_G, "gagLine")
  if f then f() end
end

-- { pattern, rewrite(pct) }: each turns a percentage line into real numbers
local REGEN = {
  { "^Ki:%s*(%d+)%%%s*KI REGEN: (%d+)%%%s*$", function(P, pct)
      if not P.MaxKi then return end
      local regen = math.floor(P.MaxKi * pct / 100)
      P.KiRegen = regen
      return string.format("\n<dim_gray>Ki<white>:    %-27s<dim_gray> KI REGEN<white>: %s\n", fmt(P.Ki or 0), fmt(regen))
    end },
  { "^GodKi:%s*(%d+)%%%s*GODKI REGEN: (%d+)%%%s*$", function(P, pct)
      if not P.MaxGK then return end
      local regen = math.floor(P.MaxGK * pct / 100)
      P.GKRegen = regen
      return string.format("\n<dim_gray>GodKi<white>: %-27s<dim_gray> GODKI REGEN<white>: %s\n", fmt(P.GK or 0), fmt(regen))
    end },
  -- bio-androids: biomass rides on the ki pool
  { "^BioMass:%s*(%d+)%%%s*BM REGEN: (%d+)%%%s*$", function(P, pct)
      if not P.MaxKi then return end
      local regen = math.floor(P.MaxKi * pct / 100)
      P.KiRegen = regen
      return string.format("\n<dim_gray>BioMass<white>: %-24s<dim_gray> BM REGEN<white>: %s\n", fmt(P.Ki or 0), fmt(regen))
    end },
  -- androids: heat is the used part of the ki pool
  { "^Heat:%s*(%d+)%%%s*Dissipation: (%d+)%%%s*$", function(P, pct)
      if not P.MaxKi then return end
      local dissipation = math.floor(P.MaxKi * pct / 100)
      P.KiRegen = dissipation
      return string.format("\n<dim_gray>Heat<white>: %-25s<dim_gray> Dissipation<white>: %s\n",
        fmt(P.MaxKi - (P.Ki or 0)), fmt(dissipation))
    end },
}

function S.line(l)
  if type(l) ~= "string" then return end
  if l:find("^%[Pl: [%d,]+ |") then
    -- the room's gravity against your max; green once you're at it (training stops paying off)
    if not S.on.gravity then return end
    local grav, max = room().Gravity, player().MaxGravity
    if not grav or not max then return end
    cecho("[<" .. (grav >= max and "green" or "red") .. ">" .. grav .. "<white>/<red>" .. max .. "x G<white>]")
    return
  end
  if l:find("^Green Orbs:") or l:find("^See 'Status', 'Train', and 'Traits' for more information%.") then
    return S.showOnce()
  end
  if not S.on.regen then return end
  for _, r in ipairs(REGEN) do
    local _, pct = l:match(r[1])
    if pct then
      local text = r[2](player(), tonumber(pct))
      if text then gag(); cecho(text) end
      return
    end
  end
end

-- ---------------------------------------------------------------- `sc` command
S.HELP = {
  { "sc show",               "The extra block, without running score" },
  { "sc extras on|off",      "The block added to the score sheet (saved)" },
  { "sc regen on|off",       "Ki/GodKi/BioMass/Heat lines in real numbers instead of % (saved)" },
  { "sc gravity on|off",     "Gravity against your max on the prompt (saved)" },
  { "sc update",             "Update Score to the latest release" },
}

function S.help()
  cecho("\n<cyan>Score (sc): just type score as usual.\n")
  for _, h in ipairs(S.HELP) do cecho(string.format("  <yellow>%-20s<white>%s\n", h[1], h[2])) end
  local parts = {}
  for _, sw in ipairs(S.SWITCHES) do parts[#parts + 1] = sw[1] .. " " .. (S.on[sw[1]] and "on" or "off") end
  cecho("  <grey>" .. table.concat(parts, "   ") .. "\n")
  if not M() then cecho("  <red>The MSDP package isn't installed: Score needs it for your stats.\n") end
end

function S.command(c, arg)
  c = c and c:lower()
  if c == "show" then return S.show() end
  for _, sw in ipairs(S.SWITCHES) do
    if c == sw[1] and (arg == "on" or arg == "off") then
      S.on[c] = arg == "on"; S.save()
      return info("white", sw[2] .. ": " .. arg)
    end
  end
  S.help()
end
