-- Vendored (trimmed) from CK's Prompt trigger: parse status forms and drive
-- the per-prompt event loop. No cosmetic prompt rewriting here so the display
-- stays untouched if another prompt-handling package is installed.
local matches = multimatches[2]
local forms = matches.Forms
local Player = AL.Player

Player.Status = {}

-- Handle States [HT] [FLY] [UI]
for form in rex.split(forms or "", "(?<=]) ") do
  if form:starts("[") and form:ends("]") then
    form = form:sub(2, -2)  -- Strip off [ and ]
    if form:starts("Rage:") then
      Player.Rage = tonumber(form:sub(7, -2))
    else
      Player.Status[form] = true
    end
  end
end

-- Show bot state while learning
if not AL.API.Mode:is(AL.API.Mode.Interactive) then
  cecho(f"[<green>{AL.API.Mode:toString()}<white>][<green>{AL.API.State:toString()}<white>]")
  local gravity = AL.Room and AL.Room.Gravity or 0
  local maxGravity = AL.Player and AL.Player.MaxGravity or 0
  cecho(f"[<red>{gravity}<white> / <red>{maxGravity}x G<white>]")
end

raiseEvent("AL.onPrompt")
