Chat = Chat or {}
Chat.helpers = Chat.helpers or {}
local chat = Chat
local helpers = Chat.helpers
local defaultConfig = { activeColor = "black", inactiveColor = "black", activeBorder = "green", activeText = "green", inactiveText =
"grey", background = "black", windowBorder = "green", title = "green", floating = false, showImage = false }
local emco = require("Chat.emco")
emco.cmdLineStyleSheet = nil
chat.config = chat.config or defaultConfig
local baseStyle = Geyser.StyleSheet:new(f [[
  border-width: 2px;
  border-style: solid;
]])
local activeStyle = Geyser.StyleSheet:new(f [[
  border-color: {chat.config.activeBorder};
  background-color: {chat.config.activeColor};
]], baseStyle)
local inactiveStyle = Geyser.StyleSheet:new(f [[
  border-color: {chat.config.inactiveColor};
  background-color: {chat.config.inactiveColor};
]], baseStyle)
local adjLabelStyle = Geyser.StyleSheet:new(f [[
  background-color: rgba(0,0,0,100%);
  border: 4px double;
  border-color: {chat.config.windowBorder};
  border-radius: 4px;]])

local FLOAT_WINDOW_NAME = "Chat Float"

local default_constraints = {
    name = "Standalone Chat Container",
    x = "60%",
    y = "0%",
    width = "40%",
    height = "50%",
    titleText = "Standalone Chat",
    autoSave = false,
    autoLoad = false,
}

local defaultConsoles = {"All", "OOC", "Tells", "Group", "Auction", "Event", "Say", "Custom"}

local EMCOfilename = getMudletHomeDir() .. "/Chat/EMCOPrebuiltChat.lua"
local confFile = getMudletHomeDir() .. "/Chat/EMCOPrebuiltExtraOptions.lua"

function helpers.echo(msg)
    msg = msg or ""
    cecho(f "<green>Chat: <reset>{msg}\n")
end

function helpers.resetToDefaults()
    default_constraints.adjLabelstyle = adjLabelStyle:getCSS()
    chat.container = chat.container or Adjustable.Container:new(default_constraints)
    chat.config = defaultConfig
    chat.emco = emco:new({
        name = "StandaloneChatEMCO",
        x = 0,
        y = 0,
        height = "100%",
        width = "100%",
        consoles = defaultConsoles,
        allTab = true,
        allTabName = "All",
        blankLine = false,
        blink = true,
        bufferSize = 10000,
        deleteLines = 500,
        timestamp = true,
        fontSize = 12,
        font = "Ubuntu Mono",
        consoleColor = chat.config.background,
        activeTabCSS = activeStyle:getCSS(),
        inactiveTabCSS = inactiveStyle:getCSS(),
        activeTabFGColor = chat.config.activeText,
        inactiveTabFGColor = chat.config.inactiveText,
        gap = 3,
        commandLine = true,
    }, chat.container)
    helpers.retheme()
end

function helpers.retheme()
    activeStyle:set("background-color", chat.config.activeColor)
    activeStyle:set("border-color", chat.config.activeBorder)
    inactiveStyle:set("background-color", chat.config.inactiveColor)
    inactiveStyle:set("border-color", chat.config.inactiveColor)
    adjLabelStyle:set("border-color", chat.config.windowBorder)
    local als = adjLabelStyle:getCSS()
    chat.container.adjLabelstyle = als
    chat.container.adjLabel:setStyleSheet(als)
    chat.container:setTitle(chat.container.titleText, chat.config.title)
    chat.emco.activeTabCSS = activeStyle:getCSS()
    chat.emco.inactiveTabCSS = inactiveStyle:getCSS()
    chat.emco:setActiveTabFGColor(chat.config.activeText)
    chat.emco:setInactiveTabFGColor(chat.config.inactiveText)
    chat.emco:setConsoleColor(chat.config.background)
    chat.emco:switchTab(chat.emco.currentTab)
end

function helpers.setConfig(cfg, val)
    local validOptions = table.keys(chat.config)
    if not table.contains(validOptions, cfg) then
        return nil, f"invalid option: valid options are {table.concat(validOptions, ', ')}"
    end
    chat.config[cfg] = val
    helpers.retheme()
    return true
end

-- Toggles the chat window between docked (inside Mudlet) and floating (separate draggable window).
function helpers.setFloating(float)
    if float then
        if not chat.floatWindow or not (Geyser.parentWindows and Geyser.parentWindows[FLOAT_WINDOW_NAME]) then
            chat.floatWindow = Geyser.UserWindow:new({
                name = FLOAT_WINDOW_NAME,
                width = 600,
                height = 400,
                titleText = "DBI Chat",
            })
        else
            showWindow(FLOAT_WINDOW_NAME)
        end
        chat.container:changeContainer(Geyser.parentWindows[FLOAT_WINDOW_NAME])
        chat.container:move("0%", "0%")
        chat.container:resize("100%", "100%")
        chat.config.floating = true
        helpers.echo("Chat is now floating. Drag the title bar to move it anywhere.")
    else
        chat.container:changeContainer(Geyser)
        chat.container:move(default_constraints.x, default_constraints.y)
        chat.container:resize(default_constraints.width, default_constraints.height)
        if chat.floatWindow then
            hideWindow(FLOAT_WINDOW_NAME)
        end
        chat.config.floating = false
        helpers.echo("Chat is now docked in the Mudlet window.")
    end
end

-- Sets or removes the decorative background image on every EMCO console.
-- Because the image is the console's own Qt background, text always renders on top of it.
function helpers.setupImage()
    local imgPath = getMudletHomeDir() .. "/Chat/android21-4.png"
    for _, tabName in ipairs(chat.emco.consoles) do
        local con = chat.emco.mc[tabName]
        if con then
            if chat.config.showImage then
                con:setBackgroundImage(imgPath, "center")
            else
                con:resetBackgroundImage()
            end
        end
    end
end

function helpers.save()
    chat.emco:save()
    -- Save container as if docked so it loads cleanly into the main window.
    -- Floating state is restored separately via chat.config.floating.
    local savedWindowname = chat.container.windowname
    chat.container.windowname = nil
    chat.container:save()
    chat.container.windowname = savedWindowname
    table.save(confFile, chat.config)
end

function helpers.load()
    if io.exists(confFile) then
        local conf = {}
        table.load(confFile, conf)
        chat.config = table.update(chat.config, conf)
        for option, value in pairs(defaultConfig) do
            chat.config[option] = chat.config[option] or value
        end
    end
    if io.exists(EMCOfilename) then
        chat.emco:hide()
        chat.emco:load()
        for _, name in ipairs(defaultConsoles) do
            if not table.contains(chat.emco.consoles, name) then
                chat.emco:addTab(name)
            end
        end
        chat.emco:show()
    end
    chat.container:load()
    helpers.retheme()
    helpers.setupImage()
    if chat.config.floating then
        helpers.setFloating(true)
    end
end

local function startup()
    helpers.resetToDefaults()
    helpers.load()
    if chat.exitHandler then
        killAnonymousEventHandler(chat.exitHandler)
    end
    chat.exitHandler = registerAnonymousEventHandler("sysExitEvent", function() helpers.save() end)
end

if not chat.emco then
    startup()
end
