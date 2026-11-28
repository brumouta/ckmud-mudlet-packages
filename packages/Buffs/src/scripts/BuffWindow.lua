BuffWindow = BuffWindow or {}
BuffWindow.visible  = BuffWindow.visible  or false
BuffWindow.floating = BuffWindow.floating or false

local CONSOLE = "BuffStatusConsole"

-- The window's font size (`buffwnd font <size>`), saved in the profile folder
local FONT_FILE = getMudletHomeDir() .. "/BuffWindow_data.lua"
BuffWindow.DEFAULT_FONT = 9
if not BuffWindow.fontSize then
    local data = {}
    if io.exists(FONT_FILE) then pcall(table.load, FONT_FILE, data) end
    BuffWindow.fontSize = tonumber(data.fontSize) or BuffWindow.DEFAULT_FONT
end

function BuffWindow:setFont(size)
    size = tonumber(size)
    if not size then
        cecho(string.format("\n<white>Buff window font size: %d (default %d). Use <sky_blue>buffwnd font <size><white>, 6 to 30.\n",
            self.fontSize, self.DEFAULT_FONT))
        return
    end
    size = math.floor(size)
    if size < 6 or size > 30 then
        cecho("\n<red>Font size must be between 6 and 30.\n")
        return
    end
    self.fontSize = size
    pcall(table.save, FONT_FILE, { fontSize = size })
    if self.console then self.console:setFontSize(size) end
    cecho(string.format("\n<white>Buff window font size set to %d.\n", size))
end

local function fmt(secs)
    secs = math.max(0, math.floor(secs))
    if secs < 60 then
        return string.format("%ds", secs)
    end
    return string.format("%dm %ds", math.floor(secs / 60), secs % 60)
end

-- Returns color tag based on how much of the buff duration remains (0-1).
local function pctColor(pct)
    if pct > 0.5 then return "green"
    elseif pct > 0.25 then return "yellow"
    elseif pct > 0.10 then return "orange"
    else return "red" end
end

function BuffWindow:init()
    if self.container then return end

    self.container = Adjustable.Container:new({
        name        = "Buff Window",
        x           = "70%", y = "0%",
        width       = "260px", height = "350px",
        titleText   = "Buff Status",
    })

    -- Dark background behind the console
    local bg = Geyser.Label:new({
        name   = "BuffWindowBg",
        x = 0, y = 0,
        width  = "100%", height = "100%",
    }, self.container.Inside)
    bg:setStyleSheet("background-color: #0a0a0a;")

    self.console = Geyser.MiniConsole:new({
        name     = CONSOLE,
        x = 2, y = 2,
        width    = "100%-4px", height = "100%-4px",
        fontSize = self.fontSize,
        color    = "black",
        wrapAt   = 9999,
    }, self.container.Inside)
end

function BuffWindow:refresh()
    if not self.console then return end
    local now   = os.time()
    local sep   = string.rep("─", 30)

    clearWindow(CONSOLE)
    cecho(CONSOLE, f"<medium_purple>{sep}<reset>\n")
    cecho(CONSOLE, "<slate_grey>  Buff Status<reset>\n")
    cecho(CONSOLE, f"<medium_purple>{sep}<reset>\n")

    if #AutoBuff.desired == 0 then
        cecho(CONSOLE, "<ansiLightBlack>  (no buffs configured)<reset>\n")
    else
        for _, skill in ipairs(AutoBuff.desired) do
            local st  = AutoBuff.status[skill]
            local dur = AutoBuff.durations[skill]

            if st and st.active then
                if not st.castAt then
                    -- Active per MSDP but cast time unknown (buff was already up when
                    -- autobuff was enabled, or cast time hasn't been confirmed yet).
                    cecho(CONSOLE, string.format(
                        "<green>  %-18s <ansiLightBlack>active<reset>\n", skill))
                else
                    local elapsedSecs = now - st.castAt

                    if dur then
                        -- Known duration: count down
                        local remaining = dur - elapsedSecs
                        local pct       = remaining / dur
                        local color     = pctColor(pct)
                        if remaining > 0 then
                            cecho(CONSOLE, string.format(
                                "<%s>  %-18s <white>%s<reset>\n",
                                color, skill, fmt(remaining)))
                        elseif st.msdpActive then
                            -- Past our estimate but MSDP still confirms it's active —
                            -- duration is just longer than we thought; show elapsed.
                            cecho(CONSOLE, string.format(
                                "<green>  %-18s <white>~%s<reset>\n", skill, fmt(elapsedSecs)))
                        else
                            -- Past predicted expiry and MSDP hasn't confirmed it —
                            -- probably expiring right now.
                            cecho(CONSOLE, string.format(
                                "<red>  %-18s <orange>any moment...<reset>\n", skill))
                        end
                    else
                        -- Unknown duration: count up with ~ to signal it's elapsed time
                        cecho(CONSOLE, string.format(
                            "<green>  %-18s <white>~%s<reset>\n", skill, fmt(elapsedSecs)))
                    end
                end

            elseif st and not st.active then
                if not AutoBuff.allowInCombat[skill] and AutoBuff:_inCombat() then
                    cecho(CONSOLE, string.format(
                        "<yellow>  %-18s <slate_grey>paused<reset>\n", skill))
                else
                    cecho(CONSOLE, string.format(
                        "<red>  %-18s <orange>EXPIRED<reset>\n", skill))
                end
            else
                cecho(CONSOLE, string.format(
                    "<ansiLightBlack>  %-18s ?<reset>\n", skill))
            end
        end
    end

    cecho(CONSOLE, f"<medium_purple>{sep}<reset>\n")

    local state = AutoBuff.enabled and "<green>auto: on" or "<red>auto: off"

    local tickStr
    if AutoBuff.healTickAt then
        local elapsed   = (os.time() - AutoBuff.healTickAt) % 75
        local remaining = 75 - elapsed
        local tickColor = remaining <= 10 and "red" or (remaining <= 25 and "yellow" or "green")
        tickStr = string.format("<slate_grey>  heal tick<reset>: <%s>%ds<reset>", tickColor, remaining)
    else
        tickStr = "<slate_grey>  heal tick<reset>: <ansiLightBlack>--<reset>"
    end

    cecho(CONSOLE, string.format("  %s<reset>%s\n", state, tickStr))
end

function BuffWindow:_startTimer()
    deleteNamedTimer("Buffs", "BuffWindow.refresh")
    registerNamedTimer("Buffs", "BuffWindow.refresh", 1, function()
        if BuffWindow.visible then BuffWindow:refresh() end
    end, true)
end

function BuffWindow:_stopTimer()
    deleteNamedTimer("Buffs", "BuffWindow.refresh")
end

function BuffWindow:show()
    if not self.container then self:init() end
    self.container:show()
    self.visible = true
    self:refresh()
    self:_startTimer()
end

function BuffWindow:hide()
    if not self.container then return end
    self.container:hide()
    self.visible = false
    self:_stopTimer()
end

function BuffWindow:toggle()
    if self.visible then self:hide() else self:show() end
end

function BuffWindow:float()
    if not self.container then return end
    if self.floating then
        self.container:dock()
        self.floating = false
        cecho("\n<white>Buff window docked.\n")
    else
        self.container:float(260, 350)
        self.floating = true
        cecho("\n<white>Buff window floating.\n")
    end
end

-- On first load: show the window. On reload: container already exists so skip
-- show(), but restart the named timer so it's always fresh after a reload.
if not BuffWindow.container then
    BuffWindow:show()
elseif BuffWindow.visible then
    BuffWindow:_startTimer()
end
