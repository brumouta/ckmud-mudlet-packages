local ck = AL.ck
local Toggles = ck:get_table("Toggles")

local function onDisconnectionEvent(eventname)
    Toggles.firstprompt = false
end

registerNamedEventHandler("Autolearn", "onDisconnectionEvent", "sysDisconnectionEvent", onDisconnectionEvent)
registerNamedEventHandler("Autolearn", "onDisconnectionEvent", "sysConnectionEvent", onDisconnectionEvent)