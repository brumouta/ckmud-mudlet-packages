-- Majerska: clears Majerska's Cursed Canopy (Earth). Type `maj help`.
-- recall, Zeno Button, s, s, the Earth vortex; fly to the Canopy (number read from `survey`), enter,
-- `where` for the boss list, then pursue and kill each boss, weakest first. Rivals are fought off.
maj = maj or {}
local J = maj

J.attack    = J.attack or "de"   -- "<attack> <first name>" on every boss and rival
J.fightWait = J.fightWait or 300 -- seconds a boss may take to die before it's tried again
J.AREA      = "Majerska's Cursed Canopy"
J.TRAVEL    = { "recall", "press button", "s", "s", "enter vortex" }
J.bosses    = J.bosses or {}

local function info(color, msg) cecho("\n<" .. color .. ">[maj] " .. msg .. "\n") end

local run = {}
local function clear()
  for _, id in ipairs(run.trigs or {}) do killTrigger(id) end
  if run.timer then killTimer(run.timer) end
  run.trigs, run.timer = {}, nil
end
local function on(text, fn) run.trigs[#run.trigs + 1] = tempTrigger(text, fn) end
local function onRe(re, fn) run.trigs[#run.trigs + 1] = tempRegexTrigger(re, fn) end
local function timeout(secs, what, fn)
  if run.timer then killTimer(run.timer) end
  run.timer = tempTimer(secs, function()
    run.timer = nil
    if fn then return fn() end
    J.stop()
    info("yellow", "Timed out waiting for " .. what .. " - maj kill carries on from inside the Canopy")
  end)
end
local function after(secs, fn)
  if run.timer then killTimer(run.timer) end
  run.timer = tempTimer(secs, function() run.timer = nil; if run.active then fn() end end)
end

function J.stop()
  local was = run.active
  clear(); run = {}
  if was then info("yellow", "Stopped") end
end

local function key(name) return name:match("^(%S+)"):lower() end

-- ---------------------------------------------------------------- the boss list (`where`)
-- "[B][1,021,013,972,463]Malakar the Damned - Majerska's Cursed Canopy: Lower Canopy"
function J.parseBoss(l)
  local pl, name, room = l:match("^%[B%]%[([%d,]+)%](.-)%s+%- Majerska's Cursed Canopy: (.+)$")
  if not pl then return end
  return { pl = tonumber((pl:gsub(",", ""))), name = name, room = room }
end

local nextBoss

local function finish()
  clear(); run.active = false
  local skipped = {}
  for n in pairs(run.skip or {}) do skipped[#skipped + 1] = n end
  table.sort(skipped)
  if (run.killed or 0) == 0 and #skipped == 0 then
    return info("green", "No bosses listed by where: the Canopy is clear (or you aren't in it)")
  end
  info("green", "Majerska's Cursed Canopy is clear (" .. run.killed .. " killed)"
    .. (#skipped > 0 and (", skipped: " .. table.concat(skipped, ", ")) or ""))
end

local function readList()
  clear()
  local list = {}
  send("where")
  onRe([[^\[B\]\[]], function()
    local b = J.parseBoss(line or "")
    if b and not run.skip[b.name] then list[#list + 1] = b end
    after(1, function()   -- the list is done when no boss line has come for a second
      clear()
      table.sort(list, function(a, b) return a.pl < b.pl end)
      J.bosses = list
      if #list == 0 then return finish() end
      local names = {}
      for _, x in ipairs(list) do names[#names + 1] = x.name end
      info("green", #list .. " bosses, weakest first: " .. table.concat(names, ", "))
      run.queue, run.killed = list, run.killed or 0
      nextBoss()
    end)
  end)
  timeout(10, "the boss list", finish)   -- nothing listed
end

-- ---------------------------------------------------------------- one boss at a time
local fight
local function pursue()
  local b = run.boss
  clear()
  send("pursue " .. key(b.name))
  on("You have successfully tracked down", fight)
  on("You're already in the same room!!", fight)
  on("You sense no ki.", function()
    run.misses = (run.misses or 0) + 1
    if run.misses >= 3 then
      info("yellow", "Can't find " .. b.name .. ": skipping")
      run.skip[b.name] = true
      return nextBoss()
    end
    after(3, pursue)
  end)
  timeout(90, "pursue " .. key(b.name))
end

fight = function()
  local b = run.boss
  clear()
  send(J.attack .. " " .. key(b.name))
  on(b.name .. " is dead!", function()
    clear()
    run.killed = run.killed + 1
    info("green", b.name .. " down (" .. run.killed .. ")")
    after(2, nextBoss)
  end)
  -- "Death Beam who?": it moved, go after it again
  onRe([[^[A-Z][\w' ]* who\?$]], function() after(2, pursue) end)
  timeout(J.fightWait, b.name .. " to die", function()
    run.retries = (run.retries or 0) + 1
    if run.retries > 1 then
      info("yellow", b.name .. " won't die: skipping")
      run.skip[b.name] = true
      return nextBoss()
    end
    info("yellow", b.name .. " still alive after " .. J.fightWait .. "s: going after it again")
    pursue()
  end)
end

nextBoss = function()
  clear()
  run.boss = table.remove(run.queue, 1)
  run.misses, run.retries = 0, 0
  if not run.boss then return readList() end   -- check nothing is left (or a respawn)
  info("white", "Next: " .. run.boss.name .. " (" .. run.boss.room .. ")")
  pursue()
end

-- ---------------------------------------------------------------- getting there
local function travel()
  clear()
  for _, c in ipairs(J.TRAVEL) do send(c) end
  on("You step through the portal.", function()
    clear()
    send("survey")
    onRe([[^\s*(\d+)\. (.+), go \w+]], function()
      if matches[3] ~= J.AREA then return end
      clear()
      send("survey " .. matches[2] .. " fly")
      on("You land on the ground in front of " .. J.AREA .. ".", function()
        clear()
        send("enter")
        after(2, readList)
      end)
      timeout(180, "the flight to " .. J.AREA)
    end)
    timeout(15, J.AREA .. " in the survey list")
  end)
  timeout(60, "the Earth vortex")
end

function J.start(skipTravel)
  J.stop()
  run = { active = true, trigs = {}, killed = 0, queue = {}, skip = {} }
  if skipTravel then return readList() end
  info("green", "Off to " .. J.AREA)
  travel()
end

-- A rival jumps you: fight back, then pick up the boss again
function J.rival(name)
  if not run.active or run.rival then return end
  run.rival = name
  clear()
  info("yellow", "Rival: " .. name .. " - fighting back")
  send(J.attack .. " " .. key(name))
  on(name .. " is dead!", function()
    run.rival = nil
    clear()
    info("green", "Rival down")
    after(2, function() if run.boss then pursue() else readList() end end)
  end)
  timeout(J.fightWait, "the fight with " .. name)
end

-- ---------------------------------------------------------------- every line
function J.line(l)
  if type(l) ~= "string" then return end
  local rival = l:match("^(.-) flies out of nowhere and attacks you!")
  if rival then return J.rival(rival) end
end

-- ---------------------------------------------------------------- `maj` alias
J.HELP = {
  { "maj go",           "Travel to Majerska's Cursed Canopy (Earth) and kill every boss, weakest first" },
  { "maj kill",         "Already inside: read where and kill every boss" },
  { "maj attack <cmd>", "Attack used on bosses and rivals (now: " .. J.attack .. ")" },
  { "maj stop",         "Stop" },
}
function J.help()
  cecho("\n<cyan>Majerska's Cursed Canopy (maj):\n")
  for _, h in ipairs(J.HELP) do cecho(string.format("  <yellow>%-18s<white>%s\n", h[1], h[2])) end
end

function J.command(c, arg)
  if c == "go" or c == "start" then J.start(false)
  elseif c == "kill" then J.start(true)
  elseif c == "attack" and arg then J.attack = arg; info("white", "Attack: " .. arg)
  elseif c == "stop" then J.stop()
  else J.help() end
end
