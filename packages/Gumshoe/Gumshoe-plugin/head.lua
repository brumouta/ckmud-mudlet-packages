-- Gumshoe for Mudlet and the CKMud client, part 1 of 3: which one this is, and compatibility.
-- Part 2 is the script from Gumshoe.mpackage, unchanged. Part 3 (tail.lua) is the trigger, the
-- alias, repeat, and in the CKMud client the plugin dashboard and plugin control. Build with:
--   node scripts/build-plugin.cjs -o gumshoe.xml head.lua ../Gumshoe.mpackage tail.lua
-- The same gumshoe.xml installs in both: Mudlet (Package Manager) and the CKMud client (catalog).
gum = gum or {}
gum.client = type(mud) == 'table' and type(mud.plugin) == 'table' and type(mud.plugin.register) == 'function'
if not gum.client and (type(mud) == 'table' or type(getMudletVersion) ~= 'function') then
  error('Gumshoe needs Mudlet, or the CKMud client with plugin support. Update the client, then import again.')
end

if gum.client then
  -- The client's Lua has no os library. Gumshoe uses os.time for the next-case wait and
  -- os.date("%H:%M") to print when it ends. The sandbox has no time zone, so that time is UTC.
  if not os then
    os = {
      time = function() return math.floor(getEpoch()) end,
      date = function(_, t)
        local s = math.floor(t or getEpoch()) % 86400
        return ('%02d:%02d UTC'):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
      end,
    }
  end

  -- Saved files live under getMudletHomeDir() ("/package") and exist only as io.exists, not io.open.
  -- Gumshoe only uses io.open to ask whether its file is there.
  if io and not io.open and io.exists then
    io.open = function(path) return io.exists(path) or nil end
  end

  -- The client's cecho knows green, red, white, yellow, slate_grey, sky_blue and ansiLightBlack;
  -- other colour names would print as text.
  local COLOURS = { cyan = 'sky_blue', grey = 'slate_grey', gray = 'slate_grey', magenta = 'sky_blue' }
  local raw = cecho
  cecho = function(text)
    return raw((tostring(text):gsub('<(%a+)>', function(c) return COLOURS[c] and ('<' .. COLOURS[c] .. '>') end)))
  end
end
