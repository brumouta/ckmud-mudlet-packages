-- Data Lords v2.0 event automation
-- Settings can be changed live with the `dl2` alias (type `dl2 help`).
dl2 = dl2 or {}
local DL = dl2

-- ---------------------------------------------------------------- settings
DL.attack      = DL.attack or "ss"          -- attack used on bosses and rivals
DL.rivalVolley = DL.rivalVolley or 4        -- attacks queued when a rival appears
DL.loop        = DL.loop or false           -- re-request the event after Zenzeyh dies
DL.requestCmd  = "request event 18"
DL.loopDelay   = 7                          -- seconds before re-requesting
DL.loot        = "get all.tab"
DL.CHECK_AFTER = 10                         -- seconds after attacking a boss to check it became my target
DL.MAX_TRIES   = 3                          -- travel attempts per boss before giving up
DL.MAX_WAIT    = 20                         -- seconds a queued boss waits for my current target to clear

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
DL.dead = {}                      -- bosses seen dying this event: key -> true

function DL.attackBoss(boss)
  DL.boss = boss
  send("pursue " .. boss)
  send("sense " .. boss)
  send(DL.attack .. " " .. boss)
  DL.verify(boss)
end

-- Is the boss my MSDP target? ("weezp" matches "Weezpurr v2.0")
function DL.targeting(boss)
  local M = rawget(_G, "MSDP")
  local target = M and M.Target and M.Target.name
  return type(target) == "string" and target:lower():find(boss, 1, true) ~= nil
end

-- Still worth chasing? (not dead, not replaced by another boss, event running)
local function stillAfter(boss)
  return DL.active and DL.boss == boss and not DL.dead[boss]
end

-- `focus 'instant'` (or `pursue`) can fail - mid-fight, lag - and then the attack goes
-- nowhere. Shortly after attacking, the boss should be my target; if not, travel again.
function DL.verify(boss)
  if DL.verifyTimer then killTimer(DL.verifyTimer) end
  DL.verifyTimer = tempTimer(DL.CHECK_AFTER, function()
    DL.verifyTimer = nil
    if not stillAfter(boss) or next(DL.rivals) then return end   -- a rival: resume re-attacks
    if DL.targeting(boss) then DL.tries = 0; return end
    DL.retry(boss, boss .. " isn't my target")
  end)
end

function DL.retry(boss, why)
  if DL.triesFor ~= boss then DL.triesFor, DL.tries = boss, 0 end
  DL.tries = DL.tries + 1
  if DL.tries > DL.MAX_TRIES then
    DL.tries = 0
    return info("red", why .. " after " .. DL.MAX_TRIES .. " tries - giving up. `dl2 resume` tries again")
  end
  info("yellow", why .. " - travelling again (try " .. DL.tries .. "/" .. DL.MAX_TRIES .. ")")
  DL.findAndAttack(boss)
end

-- "<Name> [v]2.0 is dead!" for any event boss
DL.BOSS_KEYS = { jhet = "jhet", macubyree = "macub", weezpurr = "weezp", phenix = "phenix", daiue = "daiue", zenzeyh = "zenzeyh" }
function DL.bossDead(name)
  local key = DL.BOSS_KEYS[name:lower()]
  if key then DL.dead[key] = true end
end

-- Ask `event` where the boss is, travel there, then attack
function DL.findAndAttack(boss)
  DL.boss = boss
  if boss == "jhet" then DL.pairEngaged = true end
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
  DL.locTimer = tempTimer(10, function()          -- `event` never answered (lag)
    killTrigger(DL.locTrigger)
    if stillAfter(boss) and not next(DL.rivals) then DL.retry(boss, "No answer to `event`") end
  end)

  send("event")
end

-- Jhet and Macubyree always fight together, and people kill them in either order.
-- Track both: when one dies go after the other only if it's still alive; when both
-- are down, wait for the next boss's start line.
DL.PAIR = { jhet = "macub", macub = "jhet" }
DL.PAIR_NAMES = { jhet = "Jhet", macub = "Macubyree" }

function DL.startPair()
  DL.pairDead, DL.pairEngaged = { jhet = false, macub = false }, false
  DL.goTo("jhet")
end

function DL.pairDied(who)
  DL.pairDead = DL.pairDead or { jhet = false, macub = false }
  DL.pairDead[who] = true
  local other = DL.PAIR[who]
  if DL.pairDead[other] then
    DL.boss = nil
    info("green", "Jhet and Macubyree are both down - " .. (DL.pending and "going after the next boss" or "waiting for the next boss"))
    DL.flushPending()
  elseif DL.boss ~= other then
    info("white", DL.PAIR_NAMES[who] .. " is down - going after " .. DL.PAIR_NAMES[other])
    DL.engage(other)
  end
end

-- ---------------------------------------------------------------- waiting until free
-- A new boss's start line can arrive mid-fight (or during a rival). Travelling then
-- fails - `focus 'instant'` and `pursue` are refused in combat. So travel waits, queued,
-- until no rival is alive and MSDP shows no target - but for the target at most
-- MAX_WAIT seconds (it may never clear in a busy zone); verify() retries if it fails.
function DL.fighting()
  local M = rawget(_G, "MSDP")
  local target = M and M.Target and M.Target.name
  return type(target) == "string" and target ~= ""
end

function DL.busy()
  if next(DL.rivals) ~= nil then return true end
  return DL.fighting() and os.time() - (DL.pendingSince or os.time()) < DL.MAX_WAIT
end

-- Travel to a boss now, or as soon as we're free
function DL.goTo(boss)
  if not DL.active then return end
  if boss ~= "jhet" then DL.pairEngaged = false end   -- a later boss's start line: the pair is over
  DL.pendingSince = os.time()
  if DL.busy() then
    DL.pending = boss
    info("white", boss .. " is up - going after it once this fight is over")
    return
  end
  DL.pending = nil
  DL.findAndAttack(boss)
end

function DL.flushPending()
  if not (DL.pending and DL.active) or DL.busy() then return end
  local boss = DL.pending
  DL.pending = nil
  DL.boss = boss
  tempTimer(1, function() if DL.active and DL.boss == boss then DL.findAndAttack(boss) end end)
end

-- Attack a boss in the same area; during a rival just remember it (resume attacks it)
function DL.engage(boss)
  DL.boss = boss
  if next(DL.rivals) then return end
  DL.attackBoss(boss)
end

registerNamedEventHandler("dl2", "free after fight", "MSDP.changed", function(_, kind, field, value)
  if kind == "Target" and field == "name" and value == "" then DL.flushPending() end
end)
registerNamedTimer("dl2", "pending check", 5, function() DL.flushPending() end, true)   -- safety net

-- Loot the dead boss, then go after the next one (if any)
function DL.bossDied(nextBoss)
  send(DL.loot)
  if nextBoss then
    DL.engage(nextBoss)
  else
    DL.boss = nil
  end
end

-- ---------------------------------------------------------------- event on/off
-- ---------------------------------------------------------------- who am I
-- Your name comes from the shared MSDP package (MSDP.Player.name: from the server
-- if it sends CHARACTER_NAME, otherwise from your score sheet). Until that is known
-- (no `score` yet), it falls back to a saved name: set with `dl2 name`, or learned
-- from the request line that follows your own `request event`.
DL.SAVE_FILE = getMudletHomeDir() .. "/DataLords2.lua"
DL.REQUEST_WINDOW = 20      -- seconds after you send `request event` (or `req event`) that a request line counts as yours

local function nonEmpty(name)
  if type(name) == "string" and name ~= "" and name ~= "???" then return name end
end

-- ---------------------------------------------------------------- token spending
-- Each Data Lords v2.0 request costs tokens. Every event you request (by hand or
-- through `dl2 loop`) is recorded against the current session - one per connection -
-- and the loop stops before a request would go over the session's limit.
DL.EVENT_COST   = 10000
DL.DEFAULT_LIMIT = 100000                    -- per session; `dl2 limit` changes it, `dl2 limit off` removes it
DL.HISTORY_KEEP = 20                         -- past sessions remembered

local function newSession()
  return { started = os.time(), events = 0, spent = 0 }
end

-- Name, limit, current session and history all live in one file in your profile
function DL.save()
  pcall(table.save, DL.SAVE_FILE, { name = DL.name, limit = DL.tokenLimit, session = DL.session, history = DL.history })
end

function DL.load()
  local saved = {}
  if pcall(table.load, DL.SAVE_FILE, saved) then
    DL.name = nonEmpty(saved.name)
    DL.tokenLimit = saved.limit
    DL.session, DL.history = saved.session, saved.history
  end
  if DL.tokenLimit == nil then DL.tokenLimit = DL.DEFAULT_LIMIT end
  DL.session = DL.session or newSession()
  DL.history = DL.history or {}
end

function DL.setName(name)
  DL.name = name
  DL.save()
end

-- 100000 -> "100,000"
function DL.fmtTokens(n)
  local str = tostring(math.floor(n))
  return (str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Close the current session (kept in the history if anything was spent) and start a new one
function DL.newSession()
  if DL.session and DL.session.events > 0 then
    table.insert(DL.history, 1, DL.session)
    while #DL.history > DL.HISTORY_KEEP do table.remove(DL.history) end
  end
  DL.session = newSession()
  DL.save()
end

-- Can we afford another event? Returns false plus the reason if not.
function DL.canAfford()
  if DL.tokenLimit and DL.session.spent + DL.EVENT_COST > DL.tokenLimit then
    return false, "Session token limit reached (" .. DL.fmtTokens(DL.session.spent) .. " of " ..
                  DL.fmtTokens(DL.tokenLimit) .. " spent) - raise it with `dl2 limit` or start over with `dl2 tokens reset`"
  end
  local M = rawget(_G, "MSDP")
  local balance = M and M.Player and M.Player.Tokens
  if balance and balance < DL.EVENT_COST then
    return false, "Only " .. DL.fmtTokens(balance) .. " tokens left - an event costs " .. DL.fmtTokens(DL.EVENT_COST)
  end
  return true
end

-- One of your events was requested: record what it cost
function DL.recordEvent()
  DL.session.events = DL.session.events + 1
  DL.session.spent = DL.session.spent + DL.EVENT_COST
  DL.save()
  info("white", "Event cost " .. DL.fmtTokens(DL.EVENT_COST) .. " tokens - this session: " .. DL.fmtTokens(DL.session.spent) ..
                (DL.tokenLimit and (" of " .. DL.fmtTokens(DL.tokenLimit)) or ""))
  local ok, why = DL.canAfford()
  if not ok and DL.loop then
    DL.loop = false
    info("yellow", why .. ". Loop OFF after this event.")
  end
end

local function shared() return rawget(_G, "MSDP") end

function DL.myName()
  local M = shared()
  local name = M and nonEmpty(M.Player.name)
  if name then return name, "MSDP" end
  if DL.name then return DL.name, "saved" end
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
    DL.active, DL.zenzeyhDone, DL.endedAt, DL.pending = true, false, nil, nil
    DL.dead, DL.tries = {}, 0
    enableTrigger(DL.BOSSES)
    info("green", "Requested by me, triggers ON")
    DL.recordEvent()
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
  DL.active, DL.boss, DL.rivals, DL.pending = false, nil, {}, nil
  disableTrigger(DL.BOSSES)
  disableTrigger(DL.RIVAL_DIES)
end

DL.END_GRACE = 60            -- seconds after your event ends that Zenzeyh's death still counts

-- Zenzeyh's last words end the event. They come just BEFORE his "is dead!" line, so
-- remember that it was our event: the death trigger (outside the boss folder) needs it.
function DL.ended()
  if DL.active and not DL.zenzeyhDone then DL.endedAt = os.time() end
  DL.stop()
  info("yellow", "Event ended, triggers OFF")
end

-- Zenzeyh is the last boss: always grab the tab; with the loop on (and tokens to
-- spare) also request the next event. Only for our own event - still running, or
-- ended moments ago by his last words.
function DL.zenzeyhDied()
  local recentlyEnded = DL.endedAt and os.time() - DL.endedAt <= DL.END_GRACE
  if DL.zenzeyhDone or not (DL.active or recentlyEnded) then return end
  DL.zenzeyhDone, DL.endedAt = true, nil         -- once per event
  DL.bossDied(nil)                               -- get all.tab
  if DL.loop then
    local ok, why = DL.canAfford()
    if not ok then
      DL.loop = false
      return info("yellow", why .. ". Loop OFF.")
    end
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
  enableTrigger(DL.RIVAL_DIES)              -- boss lines keep being recorded; attacking waits

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
  info("green", "Rivals cleared, resuming")
  if DL.pending then
    DL.flushPending()
  elseif DL.boss then
    DL.attackBoss(DL.boss)
  end
end

-- Escape hatch: a rival fled or died without the usual message
function DL.forceResume()
  DL.rivals, DL.tries = {}, 0
  disableTrigger(DL.RIVAL_DIES)
  if not DL.active then return end
  local boss = DL.pending or DL.boss
  DL.pending = nil
  if boss then
    info("green", "Resuming: travelling to " .. boss)
    DL.findAndAttack(boss)
  end
end

-- ---------------------------------------------------------------- MSDP
-- The shared MSDP package subscribes to everything (COMBO_HISTORY included, for
-- the daze triggers). Say so clearly if it isn't installed.
function DL.checkMSDP()
  if shared() or DL.warnedMSDP then return end
  DL.warnedMSDP = true
  info("red", "DataLords2 needs the MSDP package. Install MSDP.mpackage from the ckmud-mudlet-packages release, then reconnect.")
end
registerNamedEventHandler("dl2", "need MSDP", "sysConnectionEvent", function() tempTimer(2, DL.checkMSDP) end)
registerNamedEventHandler("dl2", "new session", "sysConnectionEvent", function() DL.newSession() end)
tempTimer(5, DL.checkMSDP)
DL.load()

-- ---------------------------------------------------------------- `dl2` alias
DL.HELP = {
  { "dl2 help",              "Show this list" },
  { "dl2 status",            "Show event state and current settings" },
  { "dl2 loop [on|off]",     "Re-request the event after Zenzeyh dies (no arg toggles)" },
  { "dl2 attack <command>",  "Attack used on bosses and rivals, e.g. dl2 attack ss" },
  { "dl2 resume",            "Forget pending rivals and travel to the current boss again" },
  { "dl2 name [<you>]",       "Show or set your character name (used to spot your own requests)" },
  { "dl2 tokens",            "Tokens spent this session (10,000 per event) and in past sessions" },
  { "dl2 tokens reset",      "Start a new session count now" },
  { "dl2 limit <n>|off",     "Per-session token limit for the loop, e.g. dl2 limit 200k (default 100,000)" },
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
  cecho("  <white>Boss:   " .. (DL.boss or "-") .. (DL.pending and (" (queued: " .. DL.pending .. ")") or "") .. "\n")
  local rivals = rivalList()
  cecho("  <white>Rivals: " .. (#rivals > 0 and table.concat(rivals, ", ") or "-") .. "\n")
  cecho("  <white>Attack: " .. DL.attack .. "\n")
  cecho("  <white>Loop:   " .. onoff(DL.loop) .. "\n")
  cecho("  <white>Tokens: " .. DL.fmtTokens(DL.session.spent) .. " spent this session (" .. DL.session.events .. " events)" ..
        (DL.tokenLimit and (", limit " .. DL.fmtTokens(DL.tokenLimit)) or ", no limit") .. "\n")
end

function DL.tokens()
  local s = DL.session
  cecho("\n<cyan>dl2 tokens (" .. DL.fmtTokens(DL.EVENT_COST) .. " per event):\n")
  cecho("  <white>This session (since " .. os.date("%Y-%m-%d %H:%M", s.started) .. "): <yellow>" ..
        DL.fmtTokens(s.spent) .. "<white> tokens, " .. s.events .. " events\n")
  if DL.tokenLimit then
    local left = math.max(0, DL.tokenLimit - s.spent)
    cecho("  <white>Limit: " .. DL.fmtTokens(DL.tokenLimit) .. " - " .. DL.fmtTokens(left) .. " left (" ..
          math.floor(left / DL.EVENT_COST) .. " more events)\n")
  else
    cecho("  <white>Limit: none\n")
  end
  local M = rawget(_G, "MSDP")
  if M and M.Player and M.Player.Tokens then
    cecho("  <white>Your balance (MSDP): " .. DL.fmtTokens(M.Player.Tokens) .. "\n")
  end
  if #DL.history > 0 then
    cecho("  <white>Past sessions:\n")
    for i = 1, math.min(10, #DL.history) do
      local h = DL.history[i]
      cecho(string.format("    <grey>%s<white>  %s tokens, %d events\n", os.date("%Y-%m-%d %H:%M", h.started),
            DL.fmtTokens(h.spent), h.events))
    end
  end
end

-- "200000", "200,000", "200k", "1.5m" -> number; nil if it isn't one
function DL.parseTokens(text)
  local num, unit = text:lower():gsub(",", ""):match("^(%d*%.?%d+)([km]?)$")
  if not num then return nil end
  return math.floor(tonumber(num) * (unit == "k" and 1000 or unit == "m" and 1000000 or 1) + 0.5)
end

function DL.command(cmd, arg)
  if cmd == nil or cmd == "help" then
    DL.help()
  elseif cmd == "status" then
    DL.status()
  elseif cmd == "loop" then
    local want = (arg == "on") or (arg == nil and not DL.loop)
    local ok, why = DL.canAfford()
    if want and not ok then
      DL.loop = false
      return info("yellow", why .. ". Loop stays OFF.")
    end
    DL.loop = want
    info("white", "Loop " .. (DL.loop and "ON" or "OFF"))
  elseif cmd == "tokens" then
    if arg == "reset" then
      DL.newSession()
      info("white", "New session started: 0 tokens spent")
    else
      DL.tokens()
    end
  elseif cmd == "limit" and arg then
    if arg == "off" then
      DL.tokenLimit = false
    else
      local n = DL.parseTokens(arg)
      if not n or n <= 0 then return info("yellow", "Didn't understand '" .. arg .. "'. Use e.g. dl2 limit 100000, 200k or off") end
      DL.tokenLimit = n
    end
    DL.save()
    info("white", DL.tokenLimit and ("Session token limit: " .. DL.fmtTokens(DL.tokenLimit) .. " (" ..
                  math.floor(DL.tokenLimit / DL.EVENT_COST) .. " events)") or "No session token limit")
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
