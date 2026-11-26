-- MoroQuest: helpers for the Moro questline (Agent Merus, Galactic Patrol). Type `moro help`.
-- 1. The prisoner manifest: the seal's key is a letter shift ("A reads as D": every letter moved
--    3 forward), so moving each letter back gives the five names to decipher.
-- 2. The wanted bulletins: post them at the spaceports of Earth, Vegeta, Namek, Iceria and Konats,
--    by recall, the Zeno Button and the Grand Atrium's vortexes (no ship).
-- 3. The recorded transmission: fly from Galactic Federation HQ to the Galactic Patrol Station and
--    walk to its Communications Deck, where Jaco's recording plays (landmark for the Prison Planet).
moro = moro or {}
local M = moro

M.auto   = (M.auto == nil) and false or M.auto   -- send the decipher commands as soon as the manifest is read
M.attack = M.attack or "de"                      -- used on rivals that jump you on the way
M.names  = M.names or {}

local function info(color, msg) cecho("\n<" .. color .. ">[moro] " .. msg .. "\n") end

-- ---------------------------------------------------------------- 1. the prisoner manifest
-- Move every letter of word back by (to - from), keeping case
function M.decode(word, from, to)
  local shift = (to:upper():byte() - from:upper():byte()) % 26
  return (word:gsub("%a", function(c)
    local base = c:match("%u") and 65 or 97
    return string.char((c:byte() - base - shift) % 26 + base)
  end))
end

-- The whole manifest text (the game may wrap it over several lines)
function M.readManifest(text)
  text = text:gsub("%s+", " ")
  local from, to = text:match("key: (%a) reads as (%a)%.")
  local list = text:match("Priority names: (.-)%.%s*%d+ of %d+ deciphered")
  if not (from and list) then return end
  local done, total = text:match("(%d+) of (%d+) deciphered")
  M.names = {}
  for word in list:gmatch("[^,%s]+") do M.names[#M.names + 1] = M.decode(word, from, to) end
  info("green", "Key " .. from .. " = " .. to .. ": " .. table.concat(M.names, ", ")
    .. "  (" .. done .. " of " .. total .. " deciphered)")
  if M.auto then M.decipher(); return M.names end
  if cechoLink then
    cecho("<white>  click to send: ")
    for i, n in ipairs(M.names) do
      cechoLink("<yellow>decipher " .. n, function() send("decipher " .. n) end, "send decipher " .. n, true)
      if i < #M.names then cecho("<white>, ") end
    end
    cecho("\n<grey>  or moro decipher to send them all\n")
  else
    cecho("<grey>  moro decipher sends decipher for each\n")
  end
  return M.names
end

function M.decipher()
  if #M.names == 0 then return info("yellow", "No manifest read yet: look prisonmanifest") end
  for _, n in ipairs(M.names) do send("decipher " .. n) end
end

-- ---------------------------------------------------------------- 2. the wanted bulletins
-- Each leg: from anywhere, recall to King Kai's Planet, the Zeno Button to the Grand Atrium,
-- walk to the planet's vortex, then on to its spaceport. Steps: a string is sent;
-- { pursue = "x" } tracks someone (again after a rival); { survey = "Area" } reads the area's
-- number from `survey`, flies there and waits to land; { wait = "text" } waits for a line.
M.PLANETS = { "Earth", "Vegeta", "Namek", "Iceria", "Konats" }
local TO_ATRIUM = { "recall", "press button" }
M.LEGS = {
  Earth  = { "s", "s", "enter vortex", { wait = "You step through the portal." },
             { pursue = "bartender" }, "w", "s" },
  Vegeta = { "s", "e", "e", "enter vortex", { wait = "You step through the portal." },
             { pursue = "pod master" } },
  Namek  = { "s", "w", "w", "enter vortex", { wait = "You step through the portal." },
             { survey = "Guru's Compound" }, "enter", { wait = "Guru's Compound - Entrance" },
             { pursue = "guide" } },
  Iceria = { "n", "w", "w", "enter vortex", { wait = "You step through the portal." },
             { survey = "City of Zero Nexus" }, "enter", { wait = "Zero Nexus - City Gates" },
             "n", "n", "n", "w" },
  Konats = { "n", "e", "e", "enter vortex", { wait = "You step through the portal." },
             { pursue = "porter" }, "s" },
}
M.POSTED = "You pin a bulletin"

local run = {}
local function clear()
  for _, id in ipairs(run.trigs or {}) do killTrigger(id) end
  if run.timer then killTimer(run.timer) end
  run.trigs, run.timer = {}, nil
end
function M.stop()
  local was = run.active
  clear(); run = {}
  if was then info("yellow", "Stopped") end
end
local function on(text, fn) run.trigs[#run.trigs + 1] = tempTrigger(text, fn) end
local function onRe(re, fn) run.trigs[#run.trigs + 1] = tempRegexTrigger(re, fn) end
local function timeout(secs, what)
  if run.timer then killTimer(run.timer) end
  run.timer = tempTimer(secs, function()
    run.timer = nil
    M.stop()
    info("yellow", "Timed out waiting for " .. what .. " - finish this part by hand, then moro bulletins")
  end)
end

-- "Still to post: Vegeta, Namek, Iceria and Konats." / "Still to post: none."
function M.parseLeft(text)
  local list = text:match("Still to post: (.-)%.")
  if not list then return end
  local left = {}
  if list ~= "none" then
    for p in list:gsub(" and ", ", "):gmatch("[^,%s]+") do left[#left + 1] = p end
  end
  return left
end

local nextStep, nextLeg

local function stepDone() clear(); run.i = run.i + 1; nextStep() end

local function doPursue(who)
  clear()
  send("pursue " .. who)
  on("You have successfully tracked down", stepDone)
  on("You're already in the same room!!", stepDone)
  timeout(90, "pursue " .. who)
end

local function doSurvey(area, arrive)
  arrive = arrive or ("You land on the ground in front of " .. area .. ".")
  clear()
  send("survey")
  onRe([[^\s*(\d+)\. (.+), go \w+]], function()
    if matches[3] ~= area then return end
    clear()
    send("survey " .. matches[2] .. " fly")
    on(arrive, stepDone)
    timeout(180, "the flight to " .. area)
  end)
  timeout(15, area .. " in the survey list")
end

nextStep = function()
  local leg = run.leg
  if not leg then return end
  local step = leg[run.i]
  if step == nil and run.finish then return run.finish() end
  if step == nil then   -- at the spaceport
    clear()
    send("post bulletin")
    local function posted(left)
      clear()
      M.left = left
      run.leg = nil
      if #left == 0 then
        run.active = false
        info("green", "All five bulletins posted. Off to the Station's comms deck for the recorded transmission.")
        run.timer = tempTimer(2, function() run.timer = nil; M.comms() end)
        return
      end
      if run.only then run.active = false; return info("green", "Posted. Still to post: " .. table.concat(left, ", ")) end
      nextLeg()
    end
    -- "You pin a bulletin ... Still to post: Namek, Iceria and Konats." (may wrap onto more lines)
    local text
    on(M.POSTED, function()
      text = line or ""
      local left = M.parseLeft(text)
      if left then return posted(left) end
      local more = 0
      onRe([[^.*$]], function()
        more = more + 1
        text = text .. " " .. (line or "")
        local l2 = M.parseLeft(text)
        if l2 then return posted(l2) end
        if more >= 3 then posted({}) end
      end)
    end)
    timeout(15, "the bulletin on " .. run.planet)
    return
  end
  if type(step) == "string" then send(step); run.i = run.i + 1; return nextStep() end
  if step.pursue then return doPursue(step.pursue) end
  if step.survey then return doSurvey(step.survey, step.arrive) end
  if step.wait then
    clear()
    on(step.wait, stepDone)
    return timeout(step.timeout or 30, step.wait)
  end
end

local function startLeg(planet)
  run.planet, run.leg, run.i = planet, {}, 1
  for _, s in ipairs(TO_ATRIUM) do run.leg[#run.leg + 1] = s end
  for _, s in ipairs(M.LEGS[planet]) do run.leg[#run.leg + 1] = s end
  info("green", "Bulletins: off to " .. planet)
  nextStep()
end

nextLeg = function()
  local left = M.left
  for _, p in ipairs(M.PLANETS) do
    local want = not left
    for _, l in ipairs(left or {}) do if l == p then want = true end end
    if want and not run.tried[p] then run.tried[p] = true; return startLeg(p) end
  end
  run.active = false
  info("yellow", "Bulletins: nothing left to post that I know of"
    .. ((left and #left > 0) and (" (still: " .. table.concat(left, ", ") .. ")") or ""))
end

-- moro bulletins [planet]: post at every spaceport still to do, or just one
function M.bulletins(planet)
  M.stop()
  run = { active = true, tried = {}, trigs = {} }
  if planet then
    for _, p in ipairs(M.PLANETS) do
      if p:lower() == planet:lower() then run.only = true; return startLeg(p) end
    end
    run.active = false
    return info("yellow", "Planets: " .. table.concat(M.PLANETS, ", "))
  end
  nextLeg()
end

-- ---------------------------------------------------------------- 3. the recorded transmission
-- recall lands in Galactic Federation HeadQuarters; leave into space, fly to the Patrol Station
-- (from `survey`), enter its hangar and walk n, n, w to the Communications Deck, where it plays.
M.COMMS = { "recall", "leave",
  { survey = "Galactic Patrol Station", arrive = "You have arrived at Galactic Patrol Station." },
  "enter", { wait = "Patrol Station Hangar" }, "n", "n", "w",
  { wait = "The recording ends with coordinates", timeout = 60 } }

function M.comms()
  M.stop()
  run = { active = true, tried = {}, trigs = {}, planet = "the comms deck", i = 1, leg = M.COMMS }
  run.finish = function()
    clear(); run.active = false; run.leg = nil
    info("green", "Transmission played: next is the Prison Planet"
      .. (M.landmark and (", landmark " .. M.landmark .. " on the Space Map survey") or ""))
  end
  info("green", "Off to the Station's comms deck")
  nextStep()
end

-- A rival jumps you on the way: fight back, then pick the step up again (redo the pursue)
function M.rival(name)
  if not run.active or run.rival then return end
  local target = name:match("^(%S+)"):lower()
  run.rival = name
  clear()
  info("yellow", "Rival: " .. name .. " - fighting back")
  send(M.attack .. " " .. target)
  on(name .. " is dead!", function()
    run.rival = nil
    clear()
    info("green", "Rival down: back to " .. (run.planet or "the bulletins"))
    run.timer = tempTimer(1, function() run.timer = nil; if run.active then nextStep() end end)
  end)
  timeout(180, "the fight with " .. name .. " to end")
end

-- ---------------------------------------------------------------- every line
local buf
function M.line(l)
  if type(l) ~= "string" then return end
  if l:find("Here is the prisoner manifest", 1, true) then   -- (the rest may wrap onto the next line)
    return send("look prisonmanifest")
  end
  if l:find("Here are the wanted bulletins", 1, true) then
    return info("green", "Bulletins for Earth, Vegeta, Namek, Iceria and Konats: moro bulletins posts them all")
  end
  local landmark = l:match("The recording ends with coordinates: .-landmark (%d+)")
  if landmark then M.landmark = tonumber(landmark) end
  local rival = l:match("^(.-) flies out of nowhere and attacks you!")
  if rival then return M.rival(rival) end
  if l:find("^%s*Prisoner manifest%.") then buf = { l }
  elseif buf then buf[#buf + 1] = l
  else return end
  local text = table.concat(buf, " ")
  if text:find("%d+ of %d+ deciphered") then buf = nil; return M.readManifest(text) end
  if #buf >= 6 then buf = nil end   -- not a manifest after all
end

-- ---------------------------------------------------------------- `moro` alias
M.HELP = {
  { "(automatic)",             "Merus hands you the manifest: looks at it and shows the five names (click to decipher)" },
  { "moro decipher",           "Send decipher for each name" },
  { "moro auto [on|off]",      "Send the decipher commands as soon as the manifest is read (default off)" },
  { "moro decode a d <words>", "Decode words by hand with a key" },
  { "moro bulletins [planet]", "Post the wanted bulletins at every spaceport still to do (or one planet)" },
  { "moro comms",              "Go to the Station's comms deck for the recorded transmission (after the bulletins)" },
  { "moro attack <cmd>",       "Attack used on rivals that jump you on the way (default de)" },
  { "moro stop",               "Stop the bulletin or comms run" },
}
function M.help()
  cecho("\n<cyan>Moro questline (moro):\n")
  for _, h in ipairs(M.HELP) do cecho(string.format("  <yellow>%-25s<white>%s\n", h[1], h[2])) end
end

function M.command(c, arg)
  if c == "decipher" or c == "go" then M.decipher()
  elseif c == "auto" then
    if arg == "on" then M.auto = true elseif arg == "off" then M.auto = false else M.auto = not M.auto end
    info("white", "Auto decipher: " .. (M.auto and "on" or "off"))
  elseif c == "decode" and arg then
    local from, to, words = arg:match("^(%a)%s+(%a)%s+(.+)$")
    if not from then return info("yellow", "moro decode <letter> <reads as> <words>, e.g. moro decode a d Ydqwd") end
    local out = {}
    for w in words:gmatch("[^,%s]+") do out[#out + 1] = M.decode(w, from, to) end
    info("green", table.concat(out, ", "))
  elseif c == "bulletins" or c == "post" then M.bulletins(arg)
  elseif c == "comms" or c == "transmission" then M.comms()
  elseif c == "attack" and arg then M.attack = arg; info("white", "Rival attack: " .. arg)
  elseif c == "stop" then M.stop()
  else M.help() end
end
