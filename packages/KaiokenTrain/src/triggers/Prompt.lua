-- Vendored (trimmed) from CK's Prompt trigger: drive the per-prompt event
-- loop. No cosmetic prompt rewriting here so the display stays untouched if
-- another prompt-handling package is installed.

-- Show bot state while training
if not KT.API.Mode:is(KT.API.Mode.Interactive) then
  local kaioken = KT.Player.Kaioken or 0
  local max = KT.Player.MKaioken or 0
  cecho(f"[<green>{KT.API.Mode:toString()}<white>][<green>{KT.API.State:toString()}<white>][<red>x{kaioken} / x{max} K<white>]")
end

raiseEvent("KT.onPrompt")
