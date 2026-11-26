-- HP table is the public API for other packages/triggers.
-- HP.current  : current power level (raw number from MSDP)
-- HP.max      : maximum power level (raw number from MSDP)
-- HP.pct      : last calculated health percentage (0-100)
HP = HP or {}
HP.current = 0
HP.max     = 0
HP.pct     = 100

function HP:calc()
    if self.max and self.max > 0 then
        self.pct = math.floor((self.current or 0) / self.max * 100)
    else
        self.pct = 100
    end
    return self.pct
end

-- Request MSDP data on connect / reconnect
registerNamedEventHandler("Health", "HP.connect", "sysConnectionEvent", function()
    sendMSDP("REPORT", "POWERLEVEL", "POWERLEVEL_MAX")
end)

-- Update HP.current when MSDP sends current PL
registerNamedEventHandler("Health", "HP.PL", "msdp.POWERLEVEL", function()
    HP.current = tonumber(msdp.POWERLEVEL) or 0
    HP:calc()
end)

-- Update HP.max when MSDP sends max PL
registerNamedEventHandler("Health", "HP.MaxPL", "msdp.POWERLEVEL_MAX", function()
    HP.max = tonumber(msdp.POWERLEVEL_MAX) or 0
    HP:calc()
end)
