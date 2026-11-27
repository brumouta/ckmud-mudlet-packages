-- ZenoButton: the Zeno Button shortcuts. Type `zb help`.
-- `recall` takes you to King Kai's Planet, `press button` (the Zeno Button) to the Grand Atrium,
-- and each planet's vortex is two or three steps from there.
zb = zb or {}
local Z = zb

Z.ROUTES = {
  e = { planet = "Earth",  walk = { "s", "s" } },
  v = { planet = "Vegeta", walk = { "s", "e", "e" } },
  n = { planet = "Namek",  walk = { "s", "w", "w" } },
  k = { planet = "Konats", walk = { "n", "e", "e" } },
  i = { planet = "Iceria", walk = { "n", "w", "w" } },
}
Z.ORDER = { "e", "v", "n", "k", "i" }

local function info(color, msg) cecho("\n<" .. color .. ">[zb] " .. msg .. "\n") end

-- the commands that take you to a planet, from anywhere
function Z.steps(letter)
  local r = Z.ROUTES[letter]
  if not r then return nil end
  local out = { "recall", "press button" }
  for _, d in ipairs(r.walk) do out[#out + 1] = d end
  out[#out + 1] = "enter vortex"
  return out
end

function Z.go(letter)
  letter = letter and letter:sub(1, 1):lower()
  local steps = Z.steps(letter)
  if not steps then return info("red", "Unknown planet. Type `zb help`.") end
  for _, c in ipairs(steps) do send(c) end
end

function Z.help()
  info("cyan", "Zeno Button shortcuts:")
  cecho("<white>  pb    <grey>press button\n")
  for _, k in ipairs(Z.ORDER) do
    local r = Z.ROUTES[k]
    cecho(string.format("<white>  pb%s   <grey>%s: recall, press button, %s, enter vortex\n",
      k, r.planet, table.concat(r.walk, ", ")))
  end
  cecho("<white>  zb update   <grey>update this package\n")
end

function Z.command(c)
  if c == nil or c == "help" then return Z.help() end
  if Z.ROUTES[c:sub(1, 1):lower()] then return Z.go(c) end
  info("red", "Unknown command. Type `zb help`.")
end

-- The same aliases used to come as a module named "Zeno Button"; both loaded would send every
-- command twice, so the module is taken out of the profile (its file is left where it is).
function Z.dropOldModule()
  if type(getModules) ~= "function" or type(uninstallModule) ~= "function" then return end
  for _, name in ipairs(getModules() or {}) do
    if name == "Zeno Button" then
      uninstallModule(name)
      info("cyan", "Removed the old Zeno Button module: this package replaces it.")
    end
  end
end
if type(tempTimer) == "function" then tempTimer(0, Z.dropOldModule) end
