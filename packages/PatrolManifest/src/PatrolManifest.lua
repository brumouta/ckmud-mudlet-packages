-- Patrol manifest: Merus's scrambled prisoner manifest (a letter shift). Type `pm help`.
-- "The broken seal prints the Patrol key: A reads as D. Priority names: Ydqwd, Eudnnd, ..."
-- A reads as D means every letter was moved 3 forward, so moving each 3 back gives the names.
pm = pm or {}
local PM = pm

PM.auto = (PM.auto == nil) and false or PM.auto   -- pm auto on: send the decipher commands by itself
PM.names = PM.names or {}

local function info(color, msg) cecho("\n<" .. color .. ">[pm] " .. msg .. "\n") end

-- Move every letter of word back by (to - from), keeping case
function PM.decode(word, from, to)
  local shift = (to:upper():byte() - from:upper():byte()) % 26
  return (word:gsub("%a", function(c)
    local base = c:match("%u") and 65 or 97
    return string.char((c:byte() - base - shift) % 26 + base)
  end))
end

-- The whole manifest text (the game may wrap it over several lines)
function PM.read(text)
  text = text:gsub("%s+", " ")
  local from, to = text:match("key: (%a) reads as (%a)%.")
  local list = text:match("Priority names: (.-)%.%s*%d+ of %d+ deciphered")
  if not (from and list) then return end
  local done, total = text:match("(%d+) of (%d+) deciphered")
  PM.names = {}
  for word in list:gmatch("[^,%s]+") do PM.names[#PM.names + 1] = PM.decode(word, from, to) end
  info("green", "Key " .. from .. " = " .. to .. ": " .. table.concat(PM.names, ", ")
    .. "  (" .. done .. " of " .. total .. " deciphered)")
  if PM.auto then return PM.go() end
  if cechoLink then
    cecho("<white>  click to send: ")
    for i, n in ipairs(PM.names) do
      cechoLink("<yellow>decipher " .. n, function() send("decipher " .. n) end, "send decipher " .. n, true)
      if i < #PM.names then cecho("<white>, ") end
    end
    cecho("\n<grey>  or pm go to send them all\n")
  else
    cecho("<grey>  pm go sends decipher for each\n")
  end
  return PM.names
end

function PM.go()
  if #PM.names == 0 then return info("yellow", "No manifest read yet: look prisonmanifest") end
  for _, n in ipairs(PM.names) do send("decipher " .. n) end
end

-- Every line goes through here (one ^.*$ trigger): collects the manifest, which can wrap
local buf
function PM.line(l)
  if type(l) ~= "string" then return end
  if l:find("Here is the prisoner manifest", 1, true) then   -- (the rest may wrap onto the next line)
    return send("look prisonmanifest")
  end
  if l:find("^%s*Prisoner manifest%.") then buf = { l }
  elseif buf then buf[#buf + 1] = l
  else return end
  local text = table.concat(buf, " ")
  if text:find("%d+ of %d+ deciphered") then buf = nil; return PM.read(text) end
  if #buf >= 6 then buf = nil end   -- not a manifest after all
end

function PM.command(c, arg)
  if c == "go" then PM.go()
  elseif c == "auto" then
    if arg == "on" then PM.auto = true elseif arg == "off" then PM.auto = false else PM.auto = not PM.auto end
    info("white", "Auto: " .. (PM.auto and "on - sends the decipher commands as soon as it reads the manifest" or "off"))
  elseif c == "decode" and arg then
    local from, to, words = arg:match("^(%a)%s+(%a)%s+(.+)$")
    if not from then return info("yellow", "pm decode <letter> <reads as> <words>, e.g. pm decode a d Ydqwd") end
    local out = {}
    for w in words:gmatch("[^,%s]+") do out[#out + 1] = PM.decode(w, from, to) end
    info("green", table.concat(out, ", "))
  else
    cecho("\n<cyan>Patrol manifest (pm):\n"
      .. "  <yellow>(automatic)        <white>Merus hands it over: looks at it, then shows the five names (click one to send it)\n"
      .. "  <yellow>pm go              <white>Send decipher for each name\n"
      .. "  <yellow>pm auto [on|off]   <white>Send them as soon as the manifest is read (default off)\n"
      .. "  <yellow>pm decode a d <words> <white>Decode by hand with a key\n")
  end
end
