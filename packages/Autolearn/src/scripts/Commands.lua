-- The `al` command (also `AL` and `autolearn`): one setup, saved, then `al start` / `al stop`.
--   al setup                   what's set and what's missing
--   al target <mob> / al path <steps> / al recall <commands|off>   the saved setup
--   al start [target [path]]   start (with the saved setup; anything given is saved too)
--   al stop / al status / al priority ... / al features ... / al constants ... / al update
-- The old `autolearn <target> <path>` still works (and saves them); bare `autolearn` toggles.
local ck = require("__PKGNAME__")
local learn = ck:get_table("API.Learning")
local API = ck:get_table("API")
local State = ck:get_table("API.State")
local Mode = ck:get_table("API.Mode")
local Player = ck:get_table("Player")

ck:define_constant("learning.target", "")   -- what to train on, e.g. "elder" (or "elder,troll")
ck:define_constant("learning.path", "")     -- from the target to your rest spot, e.g. "n;n;n;n;w"

local function say(color, msg) cecho("<" .. color .. ">[ Autolearn ] - <white>" .. msg .. "\n") end
local function trim(s) return s and (s:gsub("^%s+", ""):gsub("%s+$", "")) or nil end
local function set(name, value) ck:set_constant(name, value or "") end
local function get(name) local v = ck:constant(name); return (v ~= nil and v ~= "") and tostring(v) or nil end
local function onoff(v) return v and "<green>on<white>" or "<red>off<white>" end

local function running() return Mode:is(Mode.Learning) end

-- ---------------------------------------------------------------- start / stop
function API:start(target, path)
    target, path = trim(target), trim(path)
    if target and target ~= "" then set("learning.target", target) end
    if path and path ~= "" then set("learning.path", path) end
    if running() then return say("yellow", "Already learning on " .. tostring(learn.target) .. ": al stop first") end
    target, path = get("learning.target"), get("learning.path")
    if not target then
        return say("yellow", "Nothing to train on yet: al target <mob> (and al path <steps>), then al start. al setup shows the rest.")
    end
    learn.gumshoe_paused = nil
    learn:toggle(target, path)
end

function API:stop()
    learn.gumshoe_paused = nil -- don't let Gumshoe start it again
    if not running() then return say("white", "Not learning") end
    learn:toggle(learn.target, learn.speedwalk)
end

-- ---------------------------------------------------------------- setup and status
local function line(ok, what, value, hint)
    cecho(string.format("  %s<white> %-10s %s%s\n", ok and "<green>ok" or "<yellow>--", what, value,
        (not ok and hint) and ("  <grey>" .. hint) or ""))
end

function API:setup()
    local target, path, recall = get("learning.target"), get("learning.path"), get("learning.recall_isolation")
    local back = path and learn.return_from(path)
    local android = API:isAndroid()
    cecho("\n<cyan>Autolearn setup<white> (saved; al start uses it)\n")
    line(target, "target", target or "not set", "al target <mob>, e.g. al target elder")
    if android then
        line(true, "path", path or "not needed (androids rest where they are)")
    else
        line(path, "path", path and (path .. (back and ("  <grey>(way back: " .. back .. ")") or "  <yellow>(can't be walked back)"))
            or "not set", "al path <steps from the target to your rest spot>, e.g. al path n;n;n;n;w")
    end
    line(recall, "recall", recall or "not set",
        "al recall <commands>: rest from any room (needed to come back after a Gumshoe case), e.g. al recall crecall;w")
    line(true, "priority", get("learning.priority") or "usual order", nil)
    line(true, "gumshoe", onoff(ck:feature("learning.pause_for_gumshoe")) .. " pause for gum repeat cases (al gumshoe on|off)")
    line(true, "gravity", onoff(ck:feature("learning.use_zeta")) .. " raise the room's gravity to your max - 1 while learning (al gravity on|off)")
    local race = API.getRace and API:getRace() or ck:constant("race")
    line(race and race ~= "???", "race", tostring(race or "???"), "type score once")
    if target and (path or android or recall) then
        cecho("<green>  Ready: al start\n")
    end
end

function API:status()
    if not running() then
        if learn.gumshoe_paused then return say("white", "Paused for Gumshoe's case: learning carries on when it's done") end
        return say("white", "Not learning. al start (al setup shows what it uses)")
    end
    local n = learn:count_to_learn()
    say("green", "Learning on " .. tostring(learn.target) .. " - " .. State:toString():gsub("<%w+>", "")
        .. (n >= 0 and (", " .. n .. " skills to go") or "")
        .. (learn:return_path() ~= "" and (", way back: " .. learn:return_path()) or ""))
end

-- ---------------------------------------------------------------- features and constants
local function list_features()
    local console = require("__PKGNAME__.console")
    local features = ck:feature_names()
    local width = 15
    for _, v in ipairs(features) do width = math.max(width, #v) end
    local s = console:header("Autolearn Features List", 80)
    if #features == 0 then echo("NO FEATURES FOUND\n") end
    for _, v in ipairs(features) do
        cecho(string.format("%" .. width .. "s : %s<reset>\n", v, ck:feature(v) and "<green>on" or "<red>off"))
    end
    console:footer(s)
    echo(" * al feature <name> on|off to change\n")
end

local function set_feature(name, switch)
    if not table.contains(ck:feature_names(), name) then return cecho("<red>No Such Feature: " .. name .. "\n") end
    ck:set_feature(name, switch == "on")
    cecho("Setting Feature(" .. name .. ") to " .. switch .. "!\n")
end

local function list_constants(prefix)
    local console = require("__PKGNAME__.console")
    prefix = prefix or ""
    local names, width, found = ck:constant_names(), 1, 0
    for _, v in ipairs(names) do width = math.max(width, #v) end
    local s = console:header(prefix ~= "" and ("Autolearn Constants List \\ prefix: '" .. prefix .. "'") or "Autolearn Constants List", 80)
    for _, v in ipairs(names) do
        if v:starts(prefix) then
            found = found + 1
            cecho(string.format("%" .. width .. "s = ", v)); display(ck:constant(v))
        end
    end
    if #names == 0 then echo("NO CONSTANTS DEFINED!\n")
    elseif found == 0 then cecho("<red>NO CONSTANTS FOUND STARTING WITH '" .. prefix .. "'\n") end
    console:footer(s)
    echo(" * al constant <name> = <value> to set\n")
end

local function set_constant(name, raw)
    if not table.contains(ck:constant_names(), name) then return echo("No Such Constant: " .. name .. "\n") end
    local fn, err = loadstring(" return " .. raw)
    if not fn then return echo("Error parsing entered lua constant value: " .. tostring(err) .. "!") end
    local value = fn()
    ck:set_constant(name, value)
    echo("Setting Constant(" .. name .. ") to "); display(value)
end

local function priority(list)
    if list then
        list = trim(list)
        if list:lower() == "clear" or list:lower() == "none" then list = "" end
        ck:set_constant("learning.priority", list)
    end
    local now = ck:constant("learning.priority")
    if now == "" then
        return echo("[ Autolearn ] - No priority: skills train in the usual order. Set one with `al priority multiform, kamehameha`\n")
    end
    echo("[ Autolearn ] - Training first, in this order: " .. now .. "\n")
    -- Check the names against your skills, so typos don't go unnoticed
    local unknown = learn.check_priority(now)
    if unknown == nil then
        cecho("<yellow>[ Autolearn ] - Can't check the names yet: type `learn` and then `al priority` again.\n")
    elseif #unknown > 0 then
        for _, u in ipairs(unknown) do
            local hint = u.suggestion and (" - did you mean '" .. u.suggestion .. "'?") or ""
            cecho("<yellow>[ Autolearn ] - Not one of your skills: '" .. u.name .. "'" .. hint .. "\n")
        end
        cecho("<yellow>[ Autolearn ] - Those are ignored. Names are the ones `learn` shows.\n")
    else
        cecho("<green>[ Autolearn ] - All of them are skills you have.\n")
    end
end

-- ---------------------------------------------------------------- help and the alias
API.HELP = {
    { "al setup",                 "What's set and what's missing" },
    { "al target <mob>",          "What to train on (saved), e.g. al target elder" },
    { "al path <steps>",          "From the target to your rest spot (saved), e.g. al path n;n;n;n;w" },
    { "al recall <cmds>|off",     "Rest from any room, e.g. al recall crecall;w (saved)" },
    { "al start [target [path]]", "Start learning (anything given is saved too)" },
    { "al stop",                  "Stop learning" },
    { "al status",                "Learning or not, and how far" },
    { "al priority [skills|clear]", "Skills to train first, e.g. al priority multiform, kamehameha" },
    { "al gumshoe on|off",        "Pause for Gumshoe's gum repeat cases (default on)" },
    { "al gravity on|off",        "Raise the room's gravity (adjust) to your max - 1 while learning (default off)" },
    { "al features / al feature <name> on|off", "All feature switches" },
    { "al constants [prefix] / al constant <name> = <value>", "All settings" },
    { "al update",                "Update Autolearn to the latest release" },
}

function API:help()
    cecho("\n<cyan>Autolearn (al):\n")
    for _, h in ipairs(API.HELP) do
        if #h[1] > 26 then cecho("  <yellow>" .. h[1] .. "\n  " .. string.rep(" ", 27) .. "<white>" .. h[2] .. "\n")
        else cecho(string.format("  <yellow>%-27s<white>%s\n", h[1], h[2])) end
    end
    cecho("<grey>  autolearn <target> <path> still works too. Panic button: lua AL.API:RESET_ALL()\n")
end

local COMMANDS = {}
COMMANDS.help = function() API:help() end
COMMANDS.setup = function() API:setup() end
COMMANDS.status = function() API:status() end
COMMANDS.start = function(arg)
    local target, path = (arg or ""):match("^(%S+)%s*(.-)$")
    API:start(target, path)
end
COMMANDS.go = COMMANDS.start
COMMANDS.stop = function() API:stop() end
COMMANDS.target = function(arg)
    if arg then set("learning.target", trim(arg)) end
    say("white", "Target: " .. (get("learning.target") or "not set (al target <mob>)"))
end
COMMANDS.path = function(arg)
    if arg then set("learning.path", (arg == "clear" or arg == "none") and "" or trim(arg)) end
    local path = get("learning.path")
    local back = path and learn.return_from(path)
    say("white", "Path to your rest spot: " .. (path or "not set (al path <steps>)")
        .. (path and (back and (" - way back: " .. back) or " - can't be walked back (only directions can)") or ""))
end
COMMANDS.recall = function(arg)
    if arg then set("learning.recall_isolation", (arg == "off" or arg == "clear" or arg == "none") and "" or trim(arg)) end
    say("white", "Rest from any room with: " .. (get("learning.recall_isolation") or "not set (rests by walking the path)"))
end
COMMANDS.priority = priority
local function switch(feature, label)
    return function(arg)
        if arg == "on" or arg == "off" then ck:set_feature(feature, arg == "on") end
        say("white", label .. ": " .. onoff(ck:feature(feature)))
    end
end
COMMANDS.gumshoe = switch("learning.pause_for_gumshoe", "Pause for Gumshoe's repeat cases")
-- (the feature is still called learning.use_zeta, its name in CK, so saved settings carry over)
COMMANDS.gravity = switch("learning.use_zeta", "Raise the gravity while learning")
COMMANDS.zeta = COMMANDS.gravity
COMMANDS.features = function() list_features() end
COMMANDS.feature = function(arg)
    local name, sw = (arg or ""):match("^(%S+)%s+(on)$")
    if not name then name, sw = (arg or ""):match("^(%S+)%s+(off)$") end
    if name then return set_feature(name, sw) end
    list_features()
end
COMMANDS.constants = function(arg)
    local name, raw = (arg or ""):match("^([%w_%.%-]+)%s*=%s*(.+)$")
    if name then return set_constant(name, raw) end
    list_constants(trim(arg))
end
COMMANDS.constant = COMMANDS.constants
COMMANDS.update = function()
    uninstallPackage("__PKGNAME__")
    installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Autolearn.mpackage")
end

-- word: the first word after al/autolearn; rest: everything after it; legacy: typed as `autolearn`
function API.command(word, rest, legacy)
    local fn = word and COMMANDS[word:lower()]
    -- "AL constant name=value" has no space before "=": split it off the word
    if not fn and word then
        local w, tail = word:match("^(%a+)([%w_%.%-]*=.*)$")
        if w and COMMANDS[w:lower()] then return COMMANDS[w:lower()](trim(tail .. " " .. (rest or ""))) end
    end
    if fn then return fn(rest) end
    if legacy then
        if not word then -- bare `autolearn`: on/off
            if running() then return API:stop() end
            return API:start()
        end
        return API:start(word, rest) -- autolearn <target> <path>
    end
    if word then say("yellow", "Unknown command: al " .. word) end
    API:help()
end
