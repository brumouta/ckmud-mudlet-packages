-- Extra numbers appended to the score sheet: damage at each boost level,
-- item tier and progress to the next one, heal factor, and training helpers.
local ck = require("__PKGNAME__")
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local Sheet = ck:get_table("API.Sheet")
local fmt = ck:get_table("math")

ck:define_feature("score.extras", true) -- the appended block
ck:define_feature("score.regen", true)  -- rewrite the %% lines into numbers
ck:define_feature("score.prompt_gravity", true) -- gravity readout on the prompt

-- Base PL needed for each item tier, ascending
local TIERS = {
    { 1000000,    1 },
    { 25000000,   2 },
    { 75000000,   3 },
    { 125000000,  4 },
    { 250000000,  5 },
    { 500000000,  6 },
    { 1500000000, 7 },
    { 3000000000, 8 },
    { 5000000000, 9 },
    { 8000000000, 10 },
}

-- Zenni for one gauntlet run
local GAUNTLET_COST = 25000000

-- Base PL, from whichever source has it. The MSDP handler only fires when the
-- value changes, so a package loaded mid-session can be waiting a long while;
-- the msdp table itself already holds the current value.
function Sheet:base_pl()
    if Player.BasePl then
        return Player.BasePl
    end
    local raw = type(msdp) == "table" and msdp.BASE_PL or nil
    local n = raw and tonumber((tostring(raw):gsub(",", "")))
    if n then
        Player.BasePl = n
    end
    return n
end

function Sheet:item_tier(base_pl)
    base_pl = base_pl or self:base_pl()
    if not base_pl then
        return nil
    end
    local tier = 0
    for _, row in ipairs(TIERS) do
        if base_pl >= row[1] then
            tier = row[2]
        end
    end
    return tier
end

-- How much more base PL until the next tier, and which tier that is
function Sheet:next_tier(base_pl)
    base_pl = base_pl or self:base_pl()
    if not base_pl then
        return nil
    end
    for _, row in ipairs(TIERS) do
        if base_pl < row[1] then
            return row[2], row[1] - base_pl
        end
    end
    return nil -- already at the top tier
end

-- The stats worth training. MSDP also reports CON, but the game does not use
-- it (it is not even on the score sheet), so it never wins this contest.
local TRAINABLE = { "STR", "SPD", "WIS", "INT" }

function Sheet:lowest_stat()
    local stat, lowest
    for _, id in ipairs(TRAINABLE) do
        local value = Player.BaseStats[id]
        if value and (lowest == nil or value < lowest) then
            stat, lowest = id, value
        end
    end
    return stat, lowest
end

-- Gravity that still trains efficiently, capped just under the max
function Sheet:training_gravity()
    local max_gravity = Player.MaxGravity
    local max_pl = Player.MaxPl or Player.Pl
    if not max_gravity or not max_pl then
        return nil
    end
    return math.max(math.min(math.floor((1 / 5000) * 0.06 * max_pl), max_gravity - 1), 1)
end

function Sheet:gauntlet_runs()
    if not Player.Zenni then
        return nil
    end
    return math.floor(Player.Zenni / GAUNTLET_COST)
end

local function line(label, value, label2, value2)
    if type(label2) == "string" then
        cecho(string.format('<dim_gray>%-14s<white>: <yellow>%-20s<dim_gray>%-12s<white>: <yellow>%s\n',
            label, value, label2, value2))
    else
        cecho(string.format('<dim_gray>%-14s<white>: <yellow>%s\n', label, value))
    end
end

-- Print the extras once per score sheet. Both anchor lines ('Green Orbs:' and
-- the closing line) only ever appear in a score, so no arming step is needed -
-- depending on one would just add a way to fail silently. Whichever lands
-- first prints; the other is swallowed by the de-dupe window.
function Sheet:show_once()
    local now = getEpoch()
    if self.last_shown and now - self.last_shown < 2 then
        return
    end
    self.last_shown = now
    if ck:feature("score.extras") then
        self:show()
    end
end

-- The whole appended block; also available on demand via the `SC` alias
function Sheet:show()
    if not Player.Stats or Player.Stats.INT == nil or Player.MaxPl == nil then
        cecho("<yellow>[ Score ] - waiting on MSDP data, try again in a moment.\n")
        return
    end

    echo("\n")
    line("PHY DAM", fmt.format(API:phy_dam()), "KI DAM", fmt.format(API:ki_dam()))
    line("PHY DAM(B)", fmt.format(API:phy_dam(false, true)), "KI DAM(B)", fmt.format(API:ki_dam(false, true)))
    line("PHY DAM(S)", fmt.format(API:phy_dam(true)), "KI DAM(S)", fmt.format(API:ki_dam(true)))
    line("PHY DAM(U)", fmt.format(API:phy_dam(true, true, true)), "KI DAM(U)", fmt.format(API:ki_dam(true, true, true)))
    line("HEAL", fmt.format(math.floor(API:heal_factor())))

    local tier = self:item_tier()
    if tier then
        local next_tier, needed = self:next_tier()
        if next_tier then
            line("ITEM TIER", tier .. "  (need " .. fmt.format(needed) ..
                " more base PL for tier " .. next_tier .. ")")
        else
            line("ITEM TIER", tier .. "  (max)")
        end
    else
        -- Say why rather than quietly dropping the line
        line("ITEM TIER", "unknown - no base PL yet (run `score` once more)")
    end

    local stat, value = self:lowest_stat()
    if stat then
        line("TRAIN NEXT", stat .. " (" .. fmt.format(value) .. ")")
    end

    local grav = self:training_gravity()
    if grav then
        line("GRAVITY", grav .. "x to train  (max " .. Player.MaxGravity .. "x)")
    end

    local runs = self:gauntlet_runs()
    if runs then
        line("GAUNTLET RUNS", fmt.format(runs))
    end
end
