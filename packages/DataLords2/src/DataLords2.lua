-- Data Lords v2.0 event automation
-- Settings can be changed live with the `dl2` alias (type `dl2 help`).
dl2 = dl2 or {}
local DL = dl2

-- ---------------------------------------------------------------- settings
DL.attack      = DL.attack or "ss"          -- attack used on bosses and rivals
DL.rivalVolley = DL.rivalVolley or 4        -- attacks queued when a rival appears
DL.loop        = DL.loop or false           -- re-request the event after Zenzeyh dies
DL.requestCmd  = "req event 18"
DL.loopDelay   = 7                          -- seconds before re-requesting
DL.loot        = "get all.tab"

-- How to reach each planet's event zone
DL.travel = {
  Earth      = { "focus 'instant' malak" },
  Namek      = { "focus 'instant' dende" },
  Vegeta     = { "focus 'instant' gine" },
  Iceria     = { "focus 'instant' innkeeper" },
  Konats     = { "focus 'instant' minotia" },
  Otherworld = { "focus 'instant' joe", "fly", "fly" },
}

-- ---------------------------------------------------------------- state
DL.BOSSES = "dl2 Bosses"   -- trigger folder enabled only during my event
DL.RIVAL_DIES = "dl2 Rival dies"
DL.active = false                 -- true between "requested by me" and the end message
DL.boss   = nil                   -- boss currently being pursued, resumed after a rival
DL.rivals = {}                    -- rivals still alive: lowercase first word -> full name

local function info(color, msg)
  cecho("\n<" .. color .. ">[dl2] " .. msg .. "\n")
end

-- ---------------------------------------------------------------- bosses
function DL.attackBoss(boss)
  DL.boss = boss
  send("pursue " .. boss)
  send("sense " .. boss)
  send(DL.attack .. " " .. boss)
end

-- Ask `event` where the boss is, travel there, then attack
function DL.findAndAttack(boss)
  if DL.locTrigger then killTrigger(DL.locTrigger) end
  if DL.locTimer then killTimer(DL.locTimer) end

  DL.locTrigger = tempRegexTrigger([[^Location:\s*(.+?)\s+Time Rem:]], function()
    killTimer(DL.locTimer)
    local location = matches[2]
    local route = DL.travel[location]
    if not route then
      info("yellow", "Unknown location: " .. location)
      return
    end
    for _, cmd in ipairs(route) do send(cmd) end
    DL.attackBoss(boss)
  end, 1)
  DL.locTimer = tempTimer(10, function() killTrigger(DL.locTrigger) end)

  send("event")
end

-- Loot the dead boss, then go after the next one (if any)
function DL.bossDied(nextBoss)
  send(DL.loot)
  if nextBoss then
    DL.attackBoss(nextBoss)
  else
    DL.boss = nil
  end
end

-- ---------------------------------------------------------------- event on/off
-- ---------------------------------------------------------------- who am I
-- The MUD stopped sending MSDP CHARACTER_NAME (July 2026), so the name comes from,
-- in order: the saved name (`dl2 name`, or learned from your own request), CK's
-- score parsing, the Score package, and MSDP in case it ever comes back.
DL.SAVE_FILE = getMudletHomeDir() .. "/DataLords2.lua"
DL.REQUEST_WINDOW = 20      -- seconds after you send `req event` that a request line counts as yours

local function nonEmpty(name)
  if type(name) == "string" and name ~= "" and name ~= "???" then return name end
end

function DL.loadName()
  local saved = {}
  if pcall(table.load, DL.SAVE_FILE, saved) then DL.name = nonEmpty(saved.name) end
end

function DL.setName(name)
  DL.name = name
  pcall(table.save, DL.SAVE_FILE, { name = name })
end

function DL.myName()
  if DL.name then return DL.name, "saved" end
  local ok, ckName = pcall(function() return CK.API:getName() end)
  if ok and nonEmpty(ckName) then return ckName, "CK score" end
  local ok2, scName = pcall(function() return SC.Player.name end)
  if ok2 and nonEmpty(scName) then return scName, "Score package" end
  if msdp and nonEmpty(msdp.CHARACTER_NAME) then return msdp.CHARACTER_NAME, "MSDP" end
end

-- Remember when you (or the loop) ask for an event: the next request line is yours
function DL.onCommandSent(_, command)
  if type(command) == "string" and command:lower():match("^req%a*%s+event") then
    DL.requestedAt = os.time()
  end
end
registerNamedEventHandler("dl2", "own request", "sysDataSendRequest", DL.onCommandSent)

function DL.requested(requester)
  local justAsked = DL.requestedAt and os.time() - DL.requestedAt <= DL.REQUEST_WINDOW
  DL.requestedAt = nil
  local me = DL.myName()
  if not me and justAsked then
    DL.setName(requester)                      -- learned: it was our own request
    me = requester
    info("white", "Learned your name: " .. requester .. " (change it with `dl2 name <you>`)")
  end
  if me and requester:lower() == me:lower() then
    DL.active = true
    enableTrigger(DL.BOSSES)
    info("green", "Requested by me, triggers ON")
  else
    DL.stop()
    if me then
      info("yellow", "Requested by " .. requester .. ", triggers OFF")
    else
      info("yellow", "Requested by " .. requester .. ", triggers OFF - I don't know your name yet: `dl2 name <you>`, or request the event yourself")
    end
  end
end

function DL.stop()
  DL.active, DL.boss, DL.rivals = false, nil, {}
  disableTrigger(DL.BOSSES)
  disableTrigger(DL.RIVAL_DIES)
end

function DL.ended()
  DL.stop()
  info("yellow", "Event ended, triggers OFF")
end

function DL.zenzeyhDied()
  DL.bossDied(nil)
  if DL.loop then
    tempTimer(DL.loopDelay, function() send(DL.requestCmd) end)
    info("green", "Re-requesting the event in " .. DL.loopDelay .. "s")
  end
end

-- ---------------------------------------------------------------- rivals
-- Rivals can attack me or anyone in my group, and more can show up mid-fight.
-- The event stays paused until every rival seen so far is dead.
local function rivalList()
  local names = {}
  for _, name in pairs(DL.rivals) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function DL.rivalAppears(name, victim)
  if not DL.active then return end
  local key = name:lower()
  local isNew = DL.rivals[key] == nil
  DL.rivals[key] = name
  disableTrigger(DL.BOSSES)
  enableTrigger(DL.RIVAL_DIES)

  local who = (victim and victim:lower() ~= "you") and (" attacked " .. victim) or " attacked you"
  info("red", "Rival " .. name .. who .. ", pausing event (" .. #rivalList() .. " alive)")
  if isNew then
    for _ = 1, DL.rivalVolley do send(DL.attack .. " " .. name) end
  end
end

function DL.rivalDies(deadName)
  local key = (deadName:match("^(%S+)") or deadName):lower()
  if not DL.rivals[key] then return end

  DL.rivals[key] = nil
  send("get all")

  local left = rivalList()
  if #left > 0 then
    info("yellow", "Rival down, still fighting: " .. table.concat(left, ", "))
    send(DL.attack .. " " .. left[1])  -- switch to the next one
    return
  end
  disableTrigger(DL.RIVAL_DIES)
  tempTimer(1, DL.resume)  -- let the MUD finish the kill output
end

function DL.resume()
  if not DL.active then return end
  if next(DL.rivals) then return end  -- another rival showed up during the delay
  enableTrigger(DL.BOSSES)
  info("green", "Rivals cleared, resuming")
  if DL.boss then DL.attackBoss(DL.boss) end
end

-- Escape hatch: a rival fled or died without the usual message
function DL.forceResume()
  DL.rivals = {}
  disableTrigger(DL.RIVAL_DIES)
  DL.resume()
end

-- ---------------------------------------------------------------- MSDP
-- COMBO_HISTORY is used by the daze triggers. (CHARACTER_NAME is no longer sent.)
function DL.subscribe()
  sendMSDP("REPORT", "COMBO_HISTORY")
end
registerNamedEventHandler("dl2", "subscribe", "sysConnectionEvent", DL.subscribe)
DL.subscribe()
DL.loadName()

-- ---------------------------------------------------------------- `dl2` alias
DL.HELP = {
  { "dl2 help",              "Show this list" },
  { "dl2 status",            "Show event state and current settings" },
  { "dl2 loop [on|off]",     "Re-request the event after Zenzeyh dies (no arg toggles)" },
  { "dl2 attack <command>",  "Attack used on bosses and rivals, e.g. dl2 attack ss" },
  { "dl2 resume",            "Forget pending rivals and continue the pursuit" },
  { "dl2 name [<you>]",       "Show or set your character name (used to spot your own requests)" },
  { "dl2 off",               "Stop the event automation now" },
}

function DL.help()
  cecho("\n<cyan>Data Lords v2.0 (dl2) commands:\n")
  for _, row in ipairs(DL.HELP) do
    cecho(string.format("  <yellow>%-22s<white>%s\n", row[1], row[2]))
  end
end

function DL.status()
  local function onoff(b) return b and "<green>ON<white>" or "<red>OFF<white>" end
  cecho("\n<cyan>dl2 status:\n")
  local name, source = DL.myName()
  cecho("  <white>Name:   " .. (name and (name .. " (" .. source .. ")") or "<yellow>unknown - dl2 name <you><white>") .. "\n")
  cecho("  <white>Event:  " .. onoff(DL.active) .. "\n")
  cecho("  <white>Boss:   " .. (DL.boss or "-") .. "\n")
  local rivals = rivalList()
  cecho("  <white>Rivals: " .. (#rivals > 0 and table.concat(rivals, ", ") or "-") .. "\n")
  cecho("  <white>Attack: " .. DL.attack .. "\n")
  cecho("  <white>Loop:   " .. onoff(DL.loop) .. "\n")
end

function DL.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    DL.help()
  elseif cmd == "status" then
    DL.status()
  elseif cmd == "loop" then
    DL.loop = (arg == "on") or (arg == nil and not DL.loop)
    info("white", "Loop " .. (DL.loop and "ON" or "OFF"))
  elseif cmd == "attack" and arg then
    DL.attack = arg
    info("white", "Attack set to '" .. arg .. "'")
  elseif cmd == "resume" then
    DL.forceResume()
  elseif cmd == "name" then
    if arg then
      DL.setName(arg)
      info("white", "Name set to " .. arg)
    else
      local name, source = DL.myName()
      info("white", name and ("Your name: " .. name .. " (from " .. source .. ")") or "Name unknown - `dl2 name <you>`")
    end
  elseif cmd == "off" then
    DL.ended()
  else
    info("yellow", "Unknown command '" .. cmd .. "'. Type dl2 help")
  end
end
