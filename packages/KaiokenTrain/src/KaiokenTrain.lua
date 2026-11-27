-- kt: trains kaioken mastery to the top. Raises kaioken just above your mastery, drinks when
-- thirsty, sleeps when fatigued, wakes when rested and stops once kaioken is mastered.
-- Stats (fatigue, thirst, ki, ...) come from the MSDP package; kaioken and mastery from the prompt.
kt = kt or {}
local K = kt

-- ---------------------------------------------------------------- settings (saved)
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/kaiokentrain.lua"
K.drink = K.drink or "drink tears"
-- Mastery only climbs to 8 below the kaioken in use, so mastery + 9 leaves room for one point per
-- gain. Accelerated Mastery (pshop mastery) can land 2 or 3 in one gain: `room` extra levels keep
-- space for them. 0 = the plain mastery + 9.
K.room = K.room or 2
K.back = K.back or nil          -- commands from Jaco back to the training spot, after a Gumshoe case
if K.gumshoe == nil then K.gumshoe = true end   -- step aside for Gumshoe's `gum repeat`

function K.save()
  if type(table.save) == "function" then pcall(table.save, FILE, { drink = K.drink, room = K.room, back = K.back or "", gumshoe = K.gumshoe }) end
end

local function load()
  local t = {}
  if type(table.load) == "function" and io.open(FILE) then pcall(table.load, FILE, t) end
  if type(t.drink) == "string" and t.drink ~= "" then K.drink = t.drink end
  if tonumber(t.room) then K.room = math.max(0, math.floor(tonumber(t.room))) end
  if type(t.back) == "string" and t.back ~= "" then K.back = t.back end
  if type(t.gumshoe) == "boolean" then K.gumshoe = t.gumshoe end
end
load()

-- ---------------------------------------------------------------- state
K.on = false
K.resting = false
K.kaioken = K.kaioken or 0     -- kaioken in use (prompt)
K.mastery = nil                -- mastered kaioken (prompt / status); nil = not read yet
K.max = K.max or 120           -- the game's ceiling (kaioken getmax)
local seenKaioken = false      -- a [Kaioken: ...] line came since the last [Pl: ...] prompt
K.prompted = false             -- a prompt has been seen since connecting

local function info(color, msg) cecho("\n<" .. color .. ">[kt] <white>" .. msg .. "\n") end
local function quiet(cmd) send(cmd, false) end

local function player()
  local M = rawget(_G, "MSDP")
  return M and M.Player
end

local function connected()
  if type(getConnectionInfo) == "function" then
    local _, _, isConnected = getConnectionInfo()
    if isConnected == false then return false end
  end
  return K.prompted
end

-- How far above mastery to train: 9 plus the room (shrunk if the game wouldn't hold a level).
local function room()
  local extra = K.room
  if K.roomCap then extra = math.min(extra, K.roomCap) end
  return 9 + math.max(0, extra)
end

local function rested(P)
  return P.GK == P.MaxGK and P.Ki == P.MaxKi and P.Fatigue == P.MaxFatigue and P.Pl == P.MaxPl
end

-- ---------------------------------------------------------------- the loop (every 4 s)
function K.tick()
  if not K.on or not connected() then return end
  local P = player()
  if not P or not P.MaxFatigue then
    K.noMsdp = (K.noMsdp or 0) + 1
    if K.noMsdp == 3 then info("red", "No stats yet: KaiokenTrain needs the MSDP package (msdp status).") end
    return
  end
  if K.mastery == nil then
    -- not read yet: wait for the prompt or 'status' ("You have mastered kaioken xN."), asking again
    K.waits = (K.waits or 0) + 1
    if K.waits % 3 == 0 then quiet("status") end
    return
  end

  if K.resting then
    if rested(P) then
      send("wake")
      K.resting = false
    end
    return
  end

  local mastery = K.mastery
  local goal = K.max - 8
  local target = math.min(K.max, mastery + room())
  -- the last stretch: once the room reaches the ceiling, train at the ceiling itself until
  -- mastery is 8 below it
  local atCeiling = mastery + 9 + K.room >= K.max
  if atCeiling then target = K.max end
  if K.kaioken >= target then K.asked = nil end

  if mastery >= goal then
    -- The ceiling grows as the character does, so the max read earlier may be stale: only stop once
    -- a fresh 'kaioken getmax' confirms the goal. If it grew, training goes on.
    if K.confirmed == mastery then
      send("kaioken " .. goal)
      info("green", "Kaioken mastered completely (x" .. mastery .. ")!")
      K.stop(true)
    else
      quiet("kaioken getmax")
    end
  elseif (P.Fatigue or 0) / P.MaxFatigue < 0.20 then
    K.resting, K.asked = true, nil
    send("kaioken")
    send("land")   -- can't sleep while flying
    send("sleep")
  elseif K.kaioken < target then
    -- Asked for this level three times and still not there: the game won't allow it, so ask for
    -- one less from now on.
    if not atCeiling and K.asked == target and (K.misses or 0) >= 2 and target > mastery + 9 then
      K.roomCap = target - mastery - 10
      K.asked, K.misses = nil, 0
      info("yellow", "Kaioken " .. target .. " didn't hold, training " .. (target - 1) .. " instead.")
      target = target - 1
    elseif K.asked == target then
      K.misses = (K.misses or 0) + 1
    else
      K.asked, K.misses = target, 0
    end
    send("kaioken " .. target)
  elseif (P.Thirst or 100) < 40 then
    send(K.drink)
  end
end

-- ---------------------------------------------------------------- start / stop
function K.start()
  if K.on then return info("white", "Already training. kt stop to stop.") end
  if type(getConfig) == "function" and getConfig("enableMSDP") == false then
    info("yellow", "MSDP is off in Mudlet's settings (Settings > General): KaiokenTrain needs it for your stats.")
  end
  K.on, K.resting = true, false
  K.confirmed, K.roomCap, K.asked, K.misses, K.waits, K.noMsdp = nil, nil, nil, 0, 0, 0
  -- mastery left over from another character or a rebirth would look mastered: read it fresh
  K.mastery = nil
  quiet("kaioken getmax")
  quiet("status")
  if K.timer then killTimer(K.timer) end
  K.timer = tempTimer(4, K.tick, true)
  info("green", "Training kaioken. Best done in an isolation chamber, with something to drink (" .. K.drink .. ").")
end

function K.stop(done)
  if K.timer then killTimer(K.timer) end
  K.timer = nil
  if not done then K.gumPaused = nil end   -- kt stop while paused for Gumshoe keeps it off
  local was = K.on
  K.on, K.resting = false, false
  if was and not done then info("white", "Stopped training kaioken.") end
end

function K.toggle()
  if K.on then K.stop() else K.start() end
end

-- ---------------------------------------------------------------- game lines (every-line trigger)
local function gag()
  if type(deleteLine) == "function" then deleteLine() end
end

function K.line(l)
  if type(l) ~= "string" then return end
  local cur, mastered = l:match("^%[Kaioken: (%d+)/(%d+) %]")
  if cur then
    K.kaioken, K.mastery, seenKaioken = tonumber(cur), tonumber(mastered), true
    return
  end
  if l:find("^%[Pl: [%d,]+ |") then
    if not seenKaioken then K.kaioken = 0 end
    seenKaioken, K.prompted = false, true
    if K.on then
      cecho(string.format("<white>[<green>kt %s<white>][<red>x%d / x%s<white>]",
        K.resting and "resting" or "training", K.kaioken, K.mastery and tostring(K.mastery) or "?"))
    end
    return
  end
  local m = l:match("You have mastered kaioken x(%d+)%.$")
  if m then K.mastery = tonumber(m); return end
  local max = l:match("^Syntax: Kaioken 1%-(%d+)$")
  if max and K.on then
    K.max = tonumber(max)
    -- a fresh reply confirms there's nothing left to master
    if (K.mastery or 0) >= K.max - 8 then K.confirmed = K.mastery end
    gag()
  end
end

-- ---------------------------------------------------------------- Gumshoe's `gum repeat`
-- Just before a repeat case starts, training pauses: kaioken is dropped and, if asleep, you're woken. Once Gumshoe is back at Jaco after the case, the `kt back` commands take
-- you to the training spot and training starts again, instead of `gum repeat wait`'s commands.
local function gum() return type(rawget(_G, "gum")) == "table" and rawget(_G, "gum") or nil end

function K.gumshoeStarting()
  if not K.on or not K.gumshoe then return end
  local wasResting = K.resting
  K.stop(true)
  K.gumPaused = true
  send("kaioken")   -- don't drain fatigue through the case
  info("cyan", "Paused for Gumshoe's case: training carries on when it's done.")
  if not K.back then
    info("yellow", "No way back from Jaco set, so training stays off after the case. Set one with kt back <commands>, e.g. kt back crecall;w")
  end
  -- sent from inside the event, so it goes out before Gumshoe's first step
  if wasResting then send("wake") end
end

function K.gumshoeDone()
  if not K.gumPaused then return end
  K.gumPaused = nil
  if K.on then return end   -- started again by hand meanwhile
  if not K.back then
    return info("yellow", "Gumshoe is done, but there's no way back from Jaco (kt back): go to your training spot and kt start.")
  end
  local g = gum()
  if g and g.rep and g.rep.on == false then
    -- repeat was turned off (maybe mid-case): don't walk off from wherever you are
    return info("white", "Gumshoe's repeat is off: kt start once you're back at your training spot.")
  end
  if g and g.rep then g.rep.claimed = "KaiokenTrain" end
  info("green", "Gumshoe is done: back to training (" .. K.back .. ").")
  for part in K.back:gmatch("[^;]+") do
    local cmd = part:match("^%s*(.-)%s*$")
    if cmd ~= "" then
      if type(expandAlias) == "function" then expandAlias(cmd, false) else send(cmd) end
    end
  end
  K.start()
end

function K.disconnected()
  K.prompted, seenKaioken = false, false
end

-- ---------------------------------------------------------------- `kt` command
K.HELP = {
  { "kt start",          "Train kaioken mastery to the top (kaioken train also toggles it)" },
  { "kt stop",           "Stop" },
  { "kt status",         "Training or not, kaioken, mastery and the ceiling" },
  { "kt drink <cmd>",    "What to drink when thirsty (saved)" },
  { "kt room <0-10>",    "Extra levels above mastery + 9, for Accelerated Mastery (saved)" },
  { "kt back <cmds>|off", "After a Gumshoe repeat case: from Jaco back to the training spot (saved)" },
  { "kt gumshoe on|off", "Pause for Gumshoe's gum repeat cases (default on)" },
  { "kt update",         "Update KaiokenTrain to the latest release" },
}

function K.help()
  cecho("\n<cyan>KaiokenTrain (kt):\n")
  for _, h in ipairs(K.HELP) do cecho(string.format("  <yellow>%-20s<white>%s\n", h[1], h[2])) end
  cecho(string.format("  <grey>drink: %s   room: %d (trains at mastery + %d)   back: %s   gumshoe: %s\n",
    K.drink, K.room, 9 + K.room, K.back or "not set", K.gumshoe and "on" or "off"))
end

function K.status()
  local state = K.on and (K.resting and "<yellow>resting" or "<green>training") or "<grey>off"
  info("white", string.format("%s<white>   kaioken x%d   mastery x%s   ceiling x%d (mastered at x%d)",
    state, K.kaioken, K.mastery and tostring(K.mastery) or "? (type status)", K.max, K.max - 8))
  if not player() then info("red", "The MSDP package isn't installed: KaiokenTrain needs it for your stats.") end
end

function K.command(c, arg)
  c = c and c:lower()
  if c == "start" or c == "on" or c == "train" then K.start()
  elseif c == "stop" or c == "off" then K.stop()
  elseif c == "status" then K.status()
  elseif c == "drink" and arg then
    K.drink = arg; K.save(); info("white", "Drink: " .. arg)
  elseif c == "room" and tonumber(arg) then
    K.room = math.max(0, math.min(10, math.floor(tonumber(arg)))); K.roomCap = nil; K.save()
    info("white", "Room: " .. K.room .. " (trains at mastery + " .. (9 + K.room) .. ")")
  elseif c == "back" and arg then
    if arg:lower() == "off" or arg:lower() == "clear" then K.back = nil else K.back = arg end
    K.save(); info("white", "Back from Jaco after a Gumshoe case: " .. (K.back or "not set (training stays off)"))
  elseif c == "gumshoe" and (arg == "on" or arg == "off") then
    K.gumshoe = arg == "on"; K.save()
    info("white", "Pause for Gumshoe's repeat cases: " .. arg)
  else K.help() end
end

-- ---------------------------------------------------------------- events
if type(registerNamedEventHandler) == "function" then
  registerNamedEventHandler("KaiokenTrain", "kt disconnect", "sysDisconnectionEvent", K.disconnected)
  registerNamedEventHandler("KaiokenTrain", "kt connect", "sysConnectionEvent", K.disconnected)
  registerNamedEventHandler("KaiokenTrain", "kt gumshoe starting", "gumshoe.repeat.starting", K.gumshoeStarting)
  registerNamedEventHandler("KaiokenTrain", "kt gumshoe done", "gumshoe.repeat.done", K.gumshoeDone)
  registerNamedEventHandler("KaiokenTrain", "kt uninstall", "sysUninstallPackage", function(_, name)
    if name == "KaiokenTrain" then K.stop(true) end
  end)
end
