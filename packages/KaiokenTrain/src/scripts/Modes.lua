-- Vendored (trimmed) from CK's Modes.lua - only Kaioken and Interactive remain.
-- Fixes a CK bug where the Kaioken branch wrote _mode.String (capital S) so
-- Mode:toString() reported the wrong mode.
local ck = require("__PKGNAME__")
local Mode = ck:get_table("API.Mode", ck:make_enum(
    "Mode",
    {
        'Kaioken',
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
    elseif new_mode == Mode.Kaioken then
        _mode.string = "Kaioken"
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
