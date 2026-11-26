local action = matches[2]
if action == "on" then
    AutoBuff.enabled = true
    cecho("\n<green>Auto buff enabled.\n")
    if #AutoBuff.desired > 0 then
        -- Sync from MSDP first so already-active buffs aren't re-cast,
        -- then cast only what's genuinely missing.
        AutoBuff:_onAffects()
        AutoBuff:_retryExpired()
    else
        cecho("<yellow>  No buffs configured. Use 'autobuff add <name>' to add buffs.\n")
    end
    AutoBuff:_startRetryTimer()
else
    AutoBuff.enabled = false
    AutoBuff:_stopRetryTimer()
    cecho("\n<red>Auto buff disabled.\n")
end
