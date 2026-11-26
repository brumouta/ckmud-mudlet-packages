-- AutoBuff public API:
--   AutoBuff.enabled        true/false master toggle
--   AutoBuff.desired        list of skills to maintain (cast on enable + re-cast on expire)
--   AutoBuff.custom         user-added buffs: { skill = "expire message" }
--   AutoBuff.castMsgs       activation messages: { skill = "cast success message" }
--   AutoBuff.status         per-skill status: { active=bool, castAt=epoch, expiredAt=epoch }
--   AutoBuff:rebuff(skill)  called by expire triggers; re-casts if enabled
--   AutoBuff:onActivate(skill) called by cast triggers; sets precise castAt
--   AutoBuff:castAll()      sends focus for every skill in desired list
AutoBuff = AutoBuff or {}
AutoBuff.enabled     = AutoBuff.enabled     or false
AutoBuff.desired     = AutoBuff.desired     or {}
AutoBuff.custom      = AutoBuff.custom      or {}
AutoBuff.castMsgs    = AutoBuff.castMsgs    or {}
AutoBuff.status      = AutoBuff.status      or {}
AutoBuff.durations   = AutoBuff.durations   or {}  -- learned: { skill = seconds }
AutoBuff.affectsKeys = AutoBuff.affectsKeys or {}  -- skill -> MSDP AFFECTS name override
AutoBuff.castCmds      = AutoBuff.castCmds      or {}  -- skill -> cast command override (default: focus 'skill')
AutoBuff.itemCmds      = AutoBuff.itemCmds      or {}  -- item buff wrappers: { skill = {hold, wear} }
AutoBuff.allowInCombat = AutoBuff.allowInCombat or {}  -- skill -> true: allow recast mid-combat (default: all pause)
AutoBuff.healTickAt    = AutoBuff.healTickAt    or nil -- epoch of last heal tick (for BuffWindow display)
AutoBuff._ids         = AutoBuff._ids         or {}
AutoBuff._castIds     = AutoBuff._castIds     or {}

-- All built-in buffs: skill name -> expire message from MUD
AutoBuff.known = {
    ["barrier"]          = "The globe of energy around your body fades.",
    ["celestial drain"]  = "Your celestial aura of resurgence fades away.",
    ["celestial shield"] = "Your divine barrier slowly fades away.",
    ["demonic"]          = "Your horns recede as you feel your demonic powers fade away.",
    ["divine judgement"] = "Your body is no longer radiating divine energy.",
    ["energy shield"]    = "Your ki shield diminishes.",
    ["forcefield"]       = "Your forcefield flickers briefly and fades away.",
    ["gigantification"]  = "Your body shrinks back to its normal size.",
    ["hakai barrier"]    = "Your hakai barrier slowly fades away.",
    ["hasshuken"]        = "Your arm movements return to normal.",
    ["herculean force"]  = "Your muscles return to their normal size.",
    ["infravision"]      = "Your night vision seems to fade.",
    ["invigorate"]       = "You suddenly feel exceptionally tired...",
    ["kenjutsu"]         = "Your focus wanes, the clarity of your technique fading as your stance relaxes.",
    ["kino tsurugi"]     = "Your ki blades fade into nothing.",
    ["regenerate"]       = "Your regenerative abilities slowly fade away.",
    ["protection ballad"] = "You feel vulnerable as your protection ballad wears away.",
    ["resonance"]        = "The harmonious aura of resonance dissipates.",
    ["swiftness"]        = "You are no longer masking your movement.",
    ["tremor"]           = "You feel unease as your body loses sync with time.",
    ["wrath"]            = "Your aura subsides as your destructive wrath wanes.",
    ["zanzoken"]         = "You slow down.",
}

-- Default cast (activation) messages. User additions via 'autobuff setcast' are merged on top.
AutoBuff._defaultCastMsgs = {
    ["barrier"]          = "You are engulfed in a globe of energy.",
    ["celestial shield"] = "A shimmering barrier of divine energy surrounds you.",
    ["energy shield"]    = "You start glowing with a blue outline of ki.",
    ["hakai barrier"]    = "An impenetrable barrier of god ki forms around you.",
    ["hasshuken"]        = "You move your arms at such speed they look like 8 arms.",
    ["herculean force"]  = "Your muscles almost instantly double in size.",
    ["invigorate"]       = "You feel refreshed and full of vigor.",
    ["kenjutsu"]         = "Your stance shifts as you focus, an aura of precision and discipline sharpening your every move.",
    ["protection ballad"] = "You feel an aura of protection wash over you.",
    ["kino tsurugi"]     = "Your hands begin to glow yellow as ki blades form around them.",
    ["resonance"]        = "Your mind and spirit harmonize, forming a protective aura around you.",
    ["zanzoken"]         = "You begin moving at unbelievable speeds.",
}

-- Default cast commands for skills that don't use 'focus <skill>'.
-- User overrides via 'autobuff setcmd' are merged on top.
AutoBuff._defaultCastCmds = {
    ["protection ballad"] = "play sheet ballad",
}

-- Race/availability tags. Anything not listed is assumed universal.
AutoBuff.tags = {
    ["celestial drain"]  = "Angel",
    ["celestial shield"] = "Angel",
    ["divine judgement"] = "Angel",
    ["hakai"]            = "Angel",
    ["demonic"]          = "Demon",
    ["gigantification"]  = "?",
    ["hasshuken"]        = "?",
    ["herc"]             = "?",
    ["kenjutsu"]         = "?",
    ["tremor"]           = "?",
    ["wrath"]            = "?",
}

local saveFile = getMudletHomeDir() .. "/AutoBuff_data.lua"

function AutoBuff:save()
    table.save(saveFile, {
        desired        = self.desired,
        custom         = self.custom,
        durations      = self.durations,
        tags           = self.tags,
        castMsgs       = self.castMsgs,
        affectsKeys    = self.affectsKeys,
        castCmds       = self.castCmds,
        itemCmds       = self.itemCmds,
        allowInCombat  = self.allowInCombat,
    })
end

function AutoBuff:load()
    -- Seed castMsgs and castCmds from defaults first
    for skill, msg in pairs(self._defaultCastMsgs) do
        if not self.castMsgs[skill] then self.castMsgs[skill] = msg end
    end
    for skill, cmd in pairs(self._defaultCastCmds) do
        if not self.castCmds[skill] then self.castCmds[skill] = cmd end
    end
    local data = {}
    -- table.load loads into the second argument (does not return the table)
    local ok = pcall(table.load, saveFile, data)
    if ok and next(data) ~= nil then
        self.desired        = data.desired        or {}
        self.custom         = data.custom         or {}
        self.durations      = data.durations      or {}
        self.affectsKeys    = data.affectsKeys    or {}
        self.itemCmds       = data.itemCmds       or {}
        self.allowInCombat  = data.allowInCombat  or {}
        -- Merge user corrections over defaults
        if data.tags then
            for skill, tag in pairs(data.tags) do self.tags[skill] = tag end
        end
        if data.castMsgs then
            for skill, msg in pairs(data.castMsgs) do self.castMsgs[skill] = msg end
        end
        if data.castCmds then
            for skill, cmd in pairs(data.castCmds) do self.castCmds[skill] = cmd end
        end
    end

    -- Migrate old shorthand skill names to full MSDP-matching names
    local _renames = { herc = "herculean force", hakai = "hakai barrier", energy = "energy shield" }
    local function _mvkey(t, old, new)
        if t[old] ~= nil then t[new] = t[old]; t[old] = nil end
    end
    for old, new in pairs(_renames) do
        for i, s in ipairs(self.desired) do
            if s == old then self.desired[i] = new end
        end
        _mvkey(self.castMsgs,      old, new)
        _mvkey(self.affectsKeys,   old, new)
        _mvkey(self.itemCmds,      old, new)
        _mvkey(self.castCmds,      old, new)
        _mvkey(self.allowInCombat, old, new)
        _mvkey(self.durations,     old, new)
    end
end

-- Re-register temp triggers for custom buff expire messages
function AutoBuff:_registerAll()
    for _, id in pairs(self._ids) do killTrigger(id) end
    self._ids = {}
    for skill, msg in pairs(self.custom) do
        local id = tempTrigger(msg, string.format("AutoBuff:rebuff('%s')", skill))
        self._ids[skill] = id
    end
end

-- Re-register temp triggers for all known cast (activation) messages
function AutoBuff:_registerCastTriggers()
    for _, id in pairs(self._castIds) do killTrigger(id) end
    self._castIds = {}
    for skill, msg in pairs(self.castMsgs) do
        local id = tempTrigger(msg, string.format("AutoBuff:onActivate('%s')", skill))
        self._castIds[skill] = id
    end
end

-- Called when the MUD confirms a buff has activated.
-- Sets the precise castAt timestamp, overriding the optimistic one set in rebuff/castAll.
-- Also fires for manual casts (user types 'focus energy' directly).
function AutoBuff:onActivate(skill)
    -- Fresh table: clears stale msdpActive so _onAffects must re-confirm before
    -- treating a missing-from-AFFECTS as an expiry. Also resets castAt so the
    -- countdown starts from now rather than staying in "any moment" state.
    self.status[skill] = { active = true, castAt = os.time() }
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

-- Called by expire triggers. Learns duration, marks expired, re-casts if enabled.
-- Early-returns if MSDP already caught this expiry (avoids double-cast).
function AutoBuff:rebuff(skill)
    local now = os.time()
    local st  = self.status[skill]

    -- Learn duration using real castAt (set by onActivate) for maximum accuracy
    if st and st.active and st.castAt then
        local observed = now - st.castAt
        if observed >= 5 then
            self.durations[skill] = observed
            self:save()
        end
    end

    if not (st and st.active) then
        -- MSDP already marked this expired and handled the re-cast
        return
    end

    self.status[skill] = { active = false, expiredAt = now }
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end

    if self.enabled then
        if not self.allowInCombat[skill] and self:_inCombat() then
            -- paused during combat; retry timer will recast after the fight ends
        else
            self:_cast(skill)
            if not self.castMsgs[skill] then
                self.status[skill] = { active = true, castAt = now }
                if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
            end
        end
    end
end

-- Returns the MSDP AFFECTS key for a skill (lowercase, trimmed).
-- Defaults to the skill name itself.
function AutoBuff:_getAffectsKey(skill)
    return (self.affectsKeys[skill] or skill):lower()
end

-- Send the cast sequence for a skill.
-- castCmds overrides the default 'focus <skill>' for skills like protection ballad
-- that use a different command (e.g. 'play sheet ballad').
-- itemCmds wraps that command with hold/remove/rewear for when the instrument
-- isn't already equipped.
function AutoBuff:_cast(skill)
    local cmd = self.castCmds[skill] or string.format("focus '%s'", skill)
    local ic  = self.itemCmds[skill]
    if ic then
        send("hold " .. ic.hold)
        send(cmd)
        send("remove " .. ic.hold)
        send("wear " .. ic.wear)
    else
        send(cmd)
    end
end

function AutoBuff:_inCombat()
    return (tonumber((msdp or {}).OPPONENT_LEVEL) or 0) ~= 0
end

-- Called whenever msdp.AFFECTS changes. Compares server-side active buffs
-- against desired list and re-casts anything missing. This is the primary
-- source of truth — expire triggers are a secondary fallback.
--
-- msdpActive flag: _onAffects only re-casts a buff when MSDP itself previously
-- confirmed it as active. Without this, a freshly-cast buff that hasn't appeared
-- in MSDP AFFECTS yet (server lag) would be immediately re-cast when onActivate
-- sets active=true before MSDP catches up — causing an infinite cast loop.
function AutoBuff:_onAffects()
    local raw = (msdp or {}).AFFECTS or ""
    local active = {}
    for item in raw:gmatch("[^,]+") do
        active[item:match("^%s*(.-)%s*$"):lower()] = true
    end

    local now     = os.time()
    local changed = false
    for _, skill in ipairs(self.desired) do
        local key = self:_getAffectsKey(skill)
        local st  = self.status[skill]
        if active[key] then
            if not (st and st.active) then
                -- MSDP says it's up but we didn't know; confirm status.
                -- Preserve castAt if we have it (same session); otherwise nil —
                -- we don't know when it was cast, so don't fabricate a time.
                self.status[skill] = { active = true, castAt = st and st.castAt, msdpActive = true }
                changed = true
            elseif not st.msdpActive then
                -- Already marked active (e.g. via onActivate); MSDP now confirms it
                st.msdpActive = true
                changed = true
            end
        else
            -- Only re-cast if MSDP previously confirmed this buff was active.
            -- If msdpActive is nil the cast is still in flight (onActivate fired but
            -- MSDP hasn't seen it yet) — wait for MSDP confirmation before re-casting.
            if st and st.active and st.msdpActive then
                self.status[skill] = { active = false, expiredAt = now }
                changed = true
                if self.enabled and (self.allowInCombat[skill] or not self:_inCombat()) then
                    self:_cast(skill)
                    -- For no-cast-message skills, stamp castAt now so the countdown
                    -- is correct when MSDP confirms the buff is active again.
                    if not self.castMsgs[skill] then
                        self.status[skill].castAt = now
                    end
                end
            end
        end
    end
    if changed and BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

-- Called by the heal-tick triggers (same patterns as the healTick package).
-- Records the timestamp so BuffWindow can display a live countdown to the next tick.
function AutoBuff:_onHealTick()
    self.healTickAt = os.time()
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

-- Called on hotboot/copyover recovery. Re-subscribes to MSDP variables that
-- the server forgets after a restart (connection stays alive but state resets).
function AutoBuff:_onCopyover()
    pcall(sendMSDP, "REPORT", "AFFECTS")
    pcall(sendMSDP, "REPORT", "OPPONENT_LEVEL")
end

-- Override the cast command for a skill that doesn't use the standard 'focus <skill>'.
-- Example: autobuff setcmd protection ballad :: play sheet ballad
function AutoBuff:setcmd(skill, cmd)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    self.castCmds[skill] = cmd
    self:save()
    cecho(f"\n<green>Cast command set for '<sky_blue>{skill}<reset><green>': <white>{cmd}<reset>\n")
end

-- Set the instrument hold/rewear wrapper for a skill.
-- Optional — only needed when the instrument isn't already equipped at cast time.
-- The cast command itself comes from castCmds (or the built-in default).
-- Example: autobuff setitem protection ballad :: lute :: chainmail
function AutoBuff:setitem(skill, hold, wear)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    self.itemCmds[skill] = { hold = hold, wear = wear }
    self:save()
    local cmd = self.castCmds[skill] or string.format("focus '%s'", skill)
    cecho(f"\n<green>Item wrapper set for '<sky_blue>{skill}<reset><green>'.<reset>\n")
    cecho(f"<white>  Hold   : {hold}\n")
    cecho(f"<white>  Cast   : {cmd}\n")
    cecho(f"<white>  Wear   : {wear}\n")
end

-- Set the MSDP AFFECTS identifier for a skill (if it differs from the focus name).
function AutoBuff:setaffects(skill, key)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    self.affectsKeys[skill] = key:lower()
    self:save()
    cecho(f"\n<green>AFFECTS key for '<sky_blue>{skill}<reset><green>' set to '<white>{key}<reset><green>'.<reset>\n")
end

-- Toggle allow-during-combat for a skill.
-- By default ALL buffs pause mid-combat. This toggles the exemption for a specific skill.
-- Automatically re-casts non-exempt paused buffs when combat ends (msdp.OPPONENT_LEVEL -> 0).
function AutoBuff:setcombat(skill)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    if self.allowInCombat[skill] then
        self.allowInCombat[skill] = nil
        self:save()
        cecho(f"\n<green>'{skill}' <white>will now pause during combat (default).<reset>\n")
    else
        self.allowInCombat[skill] = true
        self:save()
        cecho(f"\n<green>'{skill}' <white>will now recast normally during combat.<reset>\n")
    end
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

function AutoBuff:castAll()
    local now      = os.time()
    local inCombat = self:_inCombat()
    for _, skill in ipairs(self.desired) do
        if not self.allowInCombat[skill] and inCombat then
            -- skip — will recast when combat ends
        else
            self:_cast(skill)
            if not self.castMsgs[skill] then
                self.status[skill] = { active = true, castAt = now }
            else
                self.status[skill] = nil
            end
        end
    end
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

function AutoBuff:_retryExpired()
    local retrying = {}
    local now = os.time()
    for _, skill in ipairs(self.desired) do
        local st  = self.status[skill]
        local dur = self.durations[skill]
        -- Past-due: active=true, castAt known, duration known, elapsed > duration,
        -- but MSDP hasn't confirmed the buff is still present. This is the "any moment"
        -- state that can get stuck after a skill rename if msdpActive was never set.
        local pastDue = st and st.active and st.castAt and dur and
                        (now - st.castAt) > dur and not st.msdpActive
        if not st or not st.active or pastDue then
            if st and st.expiredAt and (now - st.expiredAt) < 15 then
                -- recently expired, re-cast in flight
            elseif not self.allowInCombat[skill] and self:_inCombat() then
                -- paused during combat
            else
                if pastDue then
                    -- Clear the stale "any moment" entry so status is clean after recast
                    self.status[skill] = nil
                    st = nil
                end
                table.insert(retrying, skill)
                self:_cast(skill)
                if not self.castMsgs[skill] then
                    self.status[skill] = { active = true, castAt = now }
                end
            end
        end
    end
    if #retrying > 0 then
        local names = "<sky_blue>" .. table.concat(retrying, "<reset>, <sky_blue>") .. "<reset>"
        cecho(f"\n<slate_grey>  Auto buff retry:<reset> {names}\n")
        if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
    end
end

-- Named repeating timer — can't be duplicated, no ID tracking needed.
-- Replaces the old tempTimer chain which could leave ghost timers if
-- _startRetryTimer was called while one was already running.
function AutoBuff:_startRetryTimer()
    deleteNamedTimer("Buffs", "AutoBuff.retry")
    registerNamedTimer("Buffs", "AutoBuff.retry", 180, function()
        if AutoBuff.enabled then AutoBuff:_retryExpired() end
    end, true)
end

function AutoBuff:_stopRetryTimer()
    deleteNamedTimer("Buffs", "AutoBuff.retry")
end

function AutoBuff:setcast(skill, msg)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    self.castMsgs[skill] = msg
    self:_registerCastTriggers()
    self:save()
    cecho(f"\n<green>Cast message set for '<sky_blue>{skill}<reset><green>'.<reset>\n")
    cecho(f"<white>  Message: {msg}\n")
end

function AutoBuff:add(skill)
    skill = skill:lower()
    for _, s in ipairs(self.desired) do
        if s == skill then
            cecho(f"\n<yellow>{skill} is already in your desired list.\n")
            return
        end
    end
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        cecho("<white>  Use 'autobuff buffs' to see available buffs.\n")
        cecho("<white>  Use 'autobuff newbuff <skill> :: <expire message>' to add a new one.\n")
        return
    end
    table.insert(self.desired, skill)
    self:save()
    cecho(f"\n<green>Added '{skill}' to desired list.\n")
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

function AutoBuff:remove(skill)
    skill = skill:lower()
    for i, s in ipairs(self.desired) do
        if s == skill then
            table.remove(self.desired, i)
            self.status[skill] = nil
            self:save()
            cecho(f"\n<green>Removed '{skill}' from desired list.\n")
            if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
            return
        end
    end
    cecho(f"\n<yellow>'{skill}' was not in your desired list.\n")
end

function AutoBuff:newbuff(skill, msg)
    skill = skill:lower()
    if self.known[skill] then
        cecho(f"\n<yellow>'{skill}' is already a built-in buff.\n")
        return
    end
    if self.custom[skill] then
        cecho(f"\n<yellow>'{skill}' is already registered as a custom buff.\n")
        return
    end
    self.custom[skill] = msg
    self:_registerAll()
    self:save()
    cecho(f"\n<green>Registered new buff: <sky_blue>{skill}<reset>\n")
    cecho(f"<white>  Expire message : {msg}\n")
    cecho(f"<white>  Use 'autobuff add {skill}' to add it to your desired list.\n")
    cecho(f"<white>  Use 'autobuff setcast {skill} :: <message>' to register its cast message.\n")
end

function AutoBuff:delbuff(skill)
    skill = skill:lower()
    if self.known[skill] then
        cecho(f"\n<red>Cannot remove built-in buff '{skill}'.\n")
        return
    end
    if not self.custom[skill] then
        cecho(f"\n<yellow>'{skill}' is not a custom buff.\n")
        return
    end
    self.custom[skill] = nil
    self.castMsgs[skill] = nil
    self:_registerAll()
    self:_registerCastTriggers()
    for i, s in ipairs(self.desired) do
        if s == skill then table.remove(self.desired, i) break end
    end
    self.status[skill] = nil
    self:save()
    cecho(f"\n<green>Removed custom buff '{skill}'.\n")
    if BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end

function AutoBuff:settag(skill, tag)
    skill = skill:lower()
    if not self.known[skill] and not self.custom[skill] then
        cecho(f"\n<red>'{skill}' is not a known buff.\n")
        return
    end
    self.tags[skill] = tag
    self:save()
    cecho(f"\n<green>Tag for '{skill}' set to '{tag}'.\n")
end

function AutoBuff:showList()
    local sep = "<medium_purple>" .. string.rep("─", 70) .. "<reset>\n"
    local state = self.enabled and "<green>on<reset>" or "<red>off<reset>"
    cecho("\n" .. sep)
    cecho(f"<slate_grey>  Auto Buff<reset> [{state}]\n")
    cecho(sep)
    if #self.desired == 0 then
        cecho("<white>  (none -- use 'autobuff add <name>')<reset>\n")
    else
        for _, s in ipairs(self.desired) do
            cecho(f"<sky_blue>  {s}<reset>\n")
        end
    end
    cecho(sep)
end

function AutoBuff:showBuffs()
    local sep = "<medium_purple>" .. string.rep("─", 70) .. "<reset>\n"
    local inDesired = {}
    for _, s in ipairs(self.desired) do inDesired[s] = true end

    local groups = {}
    local allSkills = {}
    for skill in pairs(self.known) do table.insert(allSkills, skill) end
    table.sort(allSkills)
    for _, skill in ipairs(allSkills) do
        local tag = self.tags[skill] or "All"
        groups[tag] = groups[tag] or {}
        table.insert(groups[tag], skill)
    end

    local customSkills = {}
    for skill in pairs(self.custom) do table.insert(customSkills, skill) end
    table.sort(customSkills)
    if #customSkills > 0 then groups["Custom"] = customSkills end

    local order = {"All"}
    local otherGroups = {}
    for tag in pairs(groups) do
        if tag ~= "All" and tag ~= "Custom" then table.insert(otherGroups, tag) end
    end
    table.sort(otherGroups)
    for _, tag in ipairs(otherGroups) do table.insert(order, tag) end
    if groups["Custom"] then table.insert(order, "Custom") end

    cecho("\n" .. sep)
    local tagColor = { All = "white", Custom = "orange", ["?"] = "ansiLightBlack" }
    for _, tag in ipairs(order) do
        local skills = groups[tag]
        if skills then
            local tc = tagColor[tag] or "medium_purple"
            cecho(string.format("<slate_grey>  Buffs<reset>      <%s>[%s]<reset>\n", tc, tag))
            cecho(sep)
            for _, skill in ipairs(skills) do
                local desired = inDesired[skill] and "<green>[+]<reset>" or "   "
                local cast    = self.castMsgs[skill] and "<cyan>[C]<reset>" or "   "
                cecho(string.format("%s%s <sky_blue>%-20s<reset> <white>%s<reset>\n",
                    desired, cast, skill, self.known[skill] or self.custom[skill] or ""))
            end
            cecho(sep)
        end
    end

    cecho("<green>[+]<reset> in desired list  <cyan>[C]<reset> cast message known  |  'autobuff setcast <skill> :: <msg>'\n")
    cecho(sep)
end

registerNamedEventHandler("Buffs", "AutoBuff.connect", "sysConnectionEvent", function()
    AutoBuff:_registerAll()
    AutoBuff:_registerCastTriggers()
    if AutoBuff.enabled then AutoBuff:_startRetryTimer() end
    pcall(sendMSDP, "REPORT", "AFFECTS")
    pcall(sendMSDP, "REPORT", "OPPONENT_LEVEL")
end)

registerNamedEventHandler("Buffs", "AutoBuff.affects", "msdp.AFFECTS", function()
    AutoBuff:_onAffects()
end)

-- When combat ends (OPPONENT_LEVEL drops to 0), immediately recast any paused expired buffs.
registerNamedEventHandler("Buffs", "AutoBuff.combatEnd", "msdp.OPPONENT_LEVEL", function()
    if AutoBuff:_inCombat() or not AutoBuff.enabled then return end
    local now      = os.time()
    local recast   = false
    for _, skill in ipairs(AutoBuff.desired) do
        if not AutoBuff.allowInCombat[skill] then
            local st = AutoBuff.status[skill]
            if not st or not st.active then
                AutoBuff:_cast(skill)
                if not AutoBuff.castMsgs[skill] then
                    AutoBuff.status[skill] = { active = true, castAt = now }
                end
                recast = true
            end
        end
    end
    if recast and BuffWindow and BuffWindow.visible then BuffWindow:refresh() end
end)

AutoBuff:load()
AutoBuff:_registerAll()
AutoBuff:_registerCastTriggers()
-- Kill any stale timer from a previous load, then restart if enabled
AutoBuff:_stopRetryTimer()
if AutoBuff.enabled then AutoBuff:_startRetryTimer() end
pcall(sendMSDP, "REPORT", "AFFECTS")
pcall(sendMSDP, "REPORT", "OPPONENT_LEVEL")
