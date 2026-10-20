-- Vendored (trimmed) from CK's Prompt trigger: drive the per-prompt event
-- loop. No cosmetic prompt rewriting here so the display stays untouched if
-- another prompt-handling package is installed.

-- Show what the bot is up to while active
if CH.API.Chores.mode ~= "off" then
  cecho(f"[<green>chores:{CH.API.Chores.mode}<white>/<green>{CH.API.Chores.activity}<white>]")
end

raiseEvent("CH.onPrompt")
