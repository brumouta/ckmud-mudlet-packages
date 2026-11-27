-- Vendored (trimmed) from CK's Modes.lua - only Learning and Interactive remain
local ck = AL.ck
local Toggles = ck:get_table("Toggles")
local Mode = ck:get_table("API.Mode", ck:make_enum(
    "Mode",
    {
        'Learning',
        'Interactive'
    }
))
local API = ck:get_table("API")
local _mode = ck:get_table("API._mode", { mode = Mode.Interactive, string = "Interactive", exit_func = nil })

function Mode:switch(new_mode, exit_func)
    new_mode = new_mode or Mode.Interactive
    API.State:set(API.State.NORMAL)

    local _mode = _mode
    -- So we can go from one mode to another easily
    if _mode.mode ~= Mode.Interactive and _mode.exit_func then
        _mode.exit_func()
    end

    if new_mode == Mode.Interactive then
        _mode.string = "Interactive"
        Toggles.learning = false
    elseif new_mode == Mode.Learning then
        _mode.string = "Learning"
        Toggles.learning = true
    end
    _mode.mode = new_mode
    _mode.exit_func = exit_func
end

function Mode:is(mode)
    return mode == _mode.mode
end

function Mode:get()
    return _mode.mode
end

function Mode:toString()
    return _mode.string
end
