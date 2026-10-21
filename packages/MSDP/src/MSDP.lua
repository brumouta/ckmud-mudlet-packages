-- MSDP: the one place that talks MSDP to CKMud. Type `msdp` for the commands.
--
-- Other packages read the values from these tables (numbers already converted):
--   MSDP.Player   Pl MaxPl BasePl Ki MaxKi GK MaxGK Fatigue MaxFatigue Level Zenni Tokens
--                 EPoints Hitroll Damroll Armor MaxGravity UBS LBS DarkEnergy MaxDarkEnergy
--                 Hunger Thirst Rage ComboHistory Affects name race
--                 Stats.{STR,INT,WIS,SPD,CON}  BaseStats.{STR,INT,WIS,SPD,CON}
--   MSDP.Room     Gravity vnum
--   MSDP.Target   name level Health MaxHealth
--   MSDP.cmd_stack, MSDP.raw[<VARIABLE>] (anything not listed above, as the server sent it)
-- and these events:
--   MSDP.changed (kind, field, value)   kind = Player | Stats | BaseStats | Room | Target | MSDP | raw
--   MSDP.tick                           the server's update tick (UPDATE_EPOCH)
--   MSDP.loaded                         this package (re)loaded; copy everything again
-- and these functions:
--   MSDP:report()        (re)subscribe to every variable
--   MSDP:last_update()   seconds since the last server tick
--
-- The MUD no longer sends CHARACTER_NAME, RACE or BASE_PL, so those come from your
-- `score` sheet instead; if the server ever sends them again, its values win.
MSDP = MSDP or {}
local unpack = unpack or table.unpack
local M = MSDP

M.Player    = M.Player or {}
M.Player.Stats     = M.Player.Stats or {}
M.Player.BaseStats = M.Player.BaseStats or {}
M.Room      = M.Room or {}
M.Target    = M.Target or {}
M.raw       = M.raw or {}
M.debug     = M.debug or false

-- The variables we know how to convert: VARIABLE = { table, field, kind of value }
local NUM, STR = "number", "string"
M.MAP = {
  POWERLEVEL = { "Player", "Pl", NUM },           POWERLEVEL_MAX = { "Player", "MaxPl", NUM },
  BASE_PL = { "Player", "BasePl", NUM },          LEVEL = { "Player", "Level", NUM },
  KI = { "Player", "Ki", NUM },                   KI_MAX = { "Player", "MaxKi", NUM },
  GODKI = { "Player", "GK", NUM },                GODKI_MAX = { "Player", "MaxGK", NUM },
  FATIGUE = { "Player", "Fatigue", NUM },         FATIGUE_MAX = { "Player", "MaxFatigue", NUM },
  ZENNI = { "Player", "Zenni", NUM },             TOKENS = { "Player", "Tokens", NUM },
  EPOINTS = { "Player", "EPoints", NUM },         HITROLL = { "Player", "Hitroll", NUM },
  DAMROLL = { "Player", "Damroll", NUM },         ARMOR = { "Player", "Armor", NUM },
  MAX_GRAVITY = { "Player", "MaxGravity", NUM },  UBS = { "Player", "UBS", NUM },
  LBS = { "Player", "LBS", NUM },                 DARK_ENERGY = { "Player", "DarkEnergy", NUM },
  MAX_DENERGY = { "Player", "MaxDarkEnergy", NUM },
  HUNGER = { "Player", "Hunger", NUM },           THIRST = { "Player", "Thirst", NUM },
  RAGE = { "Player", "Rage", NUM },
  COMBO_HISTORY = { "Player", "ComboHistory", STR },
  AFFECTS = { "Player", "Affects", STR },
  CHARACTER_NAME = { "Player", "name", STR },     RACE = { "Player", "race", STR },
  ROOM_GRAVITY = { "Room", "Gravity", NUM },      ROOM_VNUM = { "Room", "vnum", NUM },
  OPPONENT_NAME = { "Target", "name", STR },      OPPONENT_LEVEL = { "Target", "level", NUM },
  OPPONENT_HEALTH = { "Target", "Health", NUM },  OPPONENT_HEALTH_MAX = { "Target", "MaxHealth", NUM },
  CMD_STACK = { "MSDP", "cmd_stack", NUM },
}
for _, stat in ipairs({ "STR", "INT", "WIS", "SPD", "CON" }) do
  M.MAP[stat] = { "Stats", stat, NUM }
  M.MAP[stat .. "_BASE"] = { "BaseStats", stat, NUM }
end

-- Asked for on every connect, in case the server can't list its variables
M.KNOWN = { "UPDATE_EPOCH" }
for name in pairs(M.MAP) do M.KNOWN[#M.KNOWN + 1] = name end
table.sort(M.KNOWN)

local function tableFor(kind)
  if kind == "Player" or kind == "Room" or kind == "Target" then return M[kind] end
  if kind == "Stats" or kind == "BaseStats" then return M.Player[kind] end
  if kind == "MSDP" then return M end
  return M.raw
end

-- Store one value and tell everyone. `source` "score" never overwrites a value the server sent.
function M.set(kind, field, value, source)
  if value == nil then return end
  if source == "score" and M._fromServer and M._fromServer[kind .. "." .. field] then return end
  if source ~= "score" then
    M._fromServer = M._fromServer or {}
    M._fromServer[kind .. "." .. field] = true
  end
  tableFor(kind)[field] = value
  raiseEvent("MSDP.changed", kind, field, value)
end

local function convert(name)
  local value = msdp and msdp[name]
  local map = M.MAP[name]
  if not map then
    M.set("raw", name, value)
    return
  end
  if map[3] == NUM then
    value = tonumber((tostring(value or ""):gsub(",", "")))
  elseif value == "" and map[1] == "Player" and (map[2] == "name" or map[2] == "race") then
    return                                    -- an empty character name/race isn't information
                                              -- (an empty OPPONENT_NAME is: it means no target)
  end
  M.set(map[1], map[2], value)
end

function M.onVariable(event)
  local name = event:sub(6)                   -- "msdp.KI" -> "KI"
  if name == "UPDATE_EPOCH" then
    if not M.ticked and M.debug then cecho("\n<yellow>[MSDP] Receiving updates\n") end
    M.ticked = true
    raiseEvent("MSDP.tick")
    return
  end
  if name == "REPORTABLE_VARIABLES" then return M.onList() end
  convert(name)
end

-- Listen for a variable (once per name, however often we subscribe)
M._listening = M._listening or {}
local function listen(name)
  if M._listening[name] then return end
  M._listening[name] = true
  registerNamedEventHandler("MSDP", name, "msdp." .. name, M.onVariable)
end

function M.subscribe(names)
  for _, name in ipairs(names) do listen(name) end
  if #names > 0 then sendMSDP("REPORT", unpack(names)) end
end

-- The server's own list of what it can report: subscribe to all of it, plus the
-- known variables (so UPDATE_EPOCH and friends are never lost if the list skips them)
function M.onList()
  local list = msdp and msdp.REPORTABLE_VARIABLES
  if type(list) ~= "table" then return end
  local seen, names = {}, {}
  local function add(name)
    if type(name) == "string" and not seen[name] then seen[name] = true; names[#names + 1] = name end
  end
  for k, v in pairs(list) do add(type(k) == "number" and v or k) end
  M.serverCount = #names
  for _, name in ipairs(M.KNOWN) do add(name) end
  table.sort(names)
  M.reportable = names
  M.subscribe(names)
end

function M:report()
  M.ticked = false
  listen("REPORTABLE_VARIABLES")
  sendMSDP("LIST", "REPORTABLE_VARIABLES")
  M.subscribe(M.reportable or M.KNOWN)
end

function M:last_update()
  return getEpoch() - tonumber((msdp and msdp.UPDATE_EPOCH) or 0)
end

-- ---------------------------------------------------------------- score sheet
-- Called by the package's score triggers
function M.fromScore(field, text)
  text = (text or ""):match("^%s*(.-)%s*$")
  if text == "" then return end
  if field == "BasePl" then
    M.set("Player", "BasePl", tonumber((text:gsub(",", ""))), "score")
  else
    M.set("Player", field, text, "score")
  end
end

-- ---------------------------------------------------------------- start up
registerNamedEventHandler("MSDP", "connect", "sysConnectionEvent", function() M:report() end)

-- "Copyover recovery complete.": the server restarted and forgot our subscriptions
function M.onCopyover()
  M:report()
end

-- MSDP only reports a variable when it changes, so after a reload replay what is
-- already in Mudlet's msdp table, then let the other packages copy it all.
function M.seed()
  if type(msdp) == "table" then
    for name in pairs(msdp) do
      if name == "UPDATE_EPOCH" then M.ticked = true
      elseif name ~= "REPORTABLE_VARIABLES" and type(msdp[name]) ~= "table" then convert(name) end
    end
  end
  raiseEvent("MSDP.loaded")
end

for _, name in ipairs(M.KNOWN) do listen(name) end
listen("REPORTABLE_VARIABLES")
M.seed()

-- ---------------------------------------------------------------- `msdp` alias
local function show(label, t, keys)
  local parts = {}
  for _, k in ipairs(keys) do
    if t[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(t[k]) end
  end
  cecho("  <yellow>" .. label .. "<white> " .. (#parts > 0 and table.concat(parts, "  ") or "-") .. "\n")
end

function M.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    cecho("\n<cyan>MSDP commands:\n")
    cecho("  <yellow>msdp status   <white>What the server is sending, and when it last did\n")
    cecho("  <yellow>msdp show     <white>All current values\n")
    cecho("  <yellow>msdp report   <white>Subscribe to every variable again\n")
    cecho("  <yellow>msdp debug on|off  <white>Say when updates start arriving\n")
  elseif cmd == "status" then
    local count = 0
    for _ in pairs(M._fromServer or {}) do count = count + 1 end
    cecho("\n<cyan>MSDP status:\n")
    cecho(string.format("  <white>Last update: %s   Variables from the server: %d   Reportable: %s\n",
      M.ticked and (M:last_update() .. "s ago") or "<red>none yet<white>", count,
      M.serverCount or "not listed yet"))
    cecho("  <white>Name: " .. tostring(M.Player.name or "-") .. "   Race: " .. tostring(M.Player.race or "-") ..
          "   Base PL: " .. tostring(M.Player.BasePl or "-") .. "  <grey>(type score to fill these in)\n")
  elseif cmd == "show" then
    cecho("\n<cyan>MSDP values:\n")
    local p = {}
    for k, v in pairs(M.Player) do if type(v) ~= "table" then p[#p + 1] = k end end
    table.sort(p)
    show("Player", M.Player, p)
    show("Stats", M.Player.Stats, { "STR", "INT", "WIS", "SPD", "CON" })
    show("BaseStats", M.Player.BaseStats, { "STR", "INT", "WIS", "SPD", "CON" })
    show("Room", M.Room, { "Gravity", "vnum" })
    show("Target", M.Target, { "name", "level", "Health", "MaxHealth" })
    local r = {}
    for k in pairs(M.raw) do r[#r + 1] = k end
    table.sort(r)
    show("Other", M.raw, r)
  elseif cmd == "report" then
    M:report()
    cecho("\n<white>[MSDP] Subscribed again\n")
  elseif cmd == "debug" and (arg == "on" or arg == "off") then
    M.debug = arg == "on"
    cecho("\n<white>[MSDP] Debug " .. arg .. "\n")
  else
    cecho("\n<yellow>[MSDP] Unknown command. Type msdp\n")
  end
end
