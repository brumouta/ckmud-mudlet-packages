-- Every game line comes through AL.line (one every-line trigger): the prompt, the score sheet's
-- name and race, the `learn` sheet, learned/mastered messages and the few lines the bot reacts to.
local ck = AL.ck
local API = ck:get_table("API")
local Player = ck:get_table("Player")
local Toggles = ck:get_table("Toggles")
local PromptFlags = ck:get_table("PromptFlags")
local learn = ck:get_table("API.Learning")
local Mode = ck:get_table("API.Mode")
local State = ck:get_table("API.State")

local L = ck:get_table("Lines", { scoreLeft = 0, learnLeft = 0 })
local BORDER = "o---------------------------------------------------------o"
local LEARN_HEADER = "Technique           Req.       Technique           Req. "
local LEARN_END = " Use 'slist' to show all skills available to your race"

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------- the prompt
-- [Pl: 90,000 | Ki: 100% ...] [HT] [FLY] [Rage: 5%]
local function prompt(forms)
  Player.Status = {}
  for bracketed in (forms or ""):gmatch("%b[]") do
    local form = bracketed:sub(2, -2)
    if form:sub(1, 5) == "Rage:" then
      Player.Rage = tonumber(form:sub(7, -2))
    else
      Player.Status[form] = true
    end
  end
  -- the bot's state while learning
  if not Mode:is(Mode.Interactive) then
    local gravity = AL.Room and AL.Room.Gravity or 0
    local maxGravity = Player.MaxGravity or 0
    cecho("[<green>" .. Mode:toString() .. "<white>][<green>" .. State:toString() .. "<white>]")
    cecho("[<red>" .. gravity .. "<white> / <red>" .. maxGravity .. "x G<white>]")
  end
  raiseEvent("AL.onPrompt")
end

-- ---------------------------------------------------------------- the learn sheet
-- A row holds one or two "<skill>   <status>" columns, where status is Mastered, Supreme,
-- Boosted, Ultimate or a percentage. A skill is lowercase letters, spaces and dashes.
local STATUS = { "Mastered", "Supreme", "Boosted", "Ultimate" }
local function nextStatus(l, from)
  local best, bestEnd
  for _, w in ipairs(STATUS) do
    local a, b = l:find(w, from, true)
    if a and (not best or a < best) then best, bestEnd = a, b end
  end
  local a, b = l:find("%d+%%", from)
  if a and (not best or a < best) then best, bestEnd = a, b end
  return best, bestEnd
end

function L.columns(l)
  local found, pos = {}, 1
  while true do
    local a, b = nextStatus(l, pos)
    if not a then break end
    -- the run of [a-z -] right before the status, starting at a letter
    local s = a
    while s > pos and l:sub(s - 1, s - 1):match("[a-z %-]") do s = s - 1 end
    local name = l:sub(s, a - 1)
    local first = name:find("[a-z]")
    if first then
      name = trim(name:sub(first))
      if name ~= "" then found[#found + 1] = { name, l:sub(a, b) } end
    end
    pos = b + 1
  end
  return found
end

local function scrapeRow(l)
  local Data = Player.Skills
  for _, col in ipairs(L.columns(l)) do
    local skill, status = col[1], col[2]
    local t = API.Skills:translate(skill)
    if status == "Mastered" or status == "Boosted" or status == "Supreme" or status == "Ultimate" then
      Data.Mastered[t] = true
      Data.Level[t] = 100
    else
      Data.Level[t] = tonumber(status:sub(1, -2))
    end
    local higher = false
    if status == "Ultimate" then Data.Ultimate[t] = true; higher = true end
    if status == "Supreme" or higher then Data.Supreme[t] = true; higher = true end
    if status == "Boosted" or higher then Data.Boosted[t] = true end
    Data.Learned[t] = true
    if Data.section then table.insert(Data.section, t) end
  end
end

local SECTIONS = {
  "^(Physical) Attacks:", "^(Ki) Attacks:", "^(AoE) Attacks:", "^(Other) Skills:",
  "^o%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%[ (Focus) Skills %]%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-o$",
}

local function learnLine(l)
  if l == LEARN_END then
    L.learnLeft = 0
    Player.Skills.section = nil
    return
  end
  scrapeRow(l)
  for _, p in ipairs(SECTIONS) do
    local name = l:match(p)
    if name then
      local section = {}
      Player.Skills.section = section
      Player.Skills.Sections[name] = section
      return
    end
  end
end

-- ---------------------------------------------------------------- every line
function AL.line(l)
  if type(l) ~= "string" then return end
  local prev = L.prev
  L.prev = l

  -- the score sheet: name, then race within the next 25 lines
  if L.scoreLeft > 0 then
    L.scoreLeft = L.scoreLeft - 1
    if l:find("^See 'Status', 'Train', and 'Traits' for more information%.") then
      L.scoreLeft = 0
    else
      local race = l:match("^Race:%s*(.-)%s*$")
      if race then API:setRace(trim(race)) end
    end
  end
  local name = l:match("^Score Information for:(.+)$")
  if name then
    API:setName(trim(name))
    L.scoreLeft = 25
    return
  end

  -- the learn sheet: its border then its header open it, for up to 99 lines
  if L.learnLeft > 0 then
    L.learnLeft = L.learnLeft - 1
    learnLine(l)
  elseif prev == BORDER and l == LEARN_HEADER then
    API.Skills.clear()
    L.learnLeft = 99
    return
  end

  if l:find("[Target: ", 1, true) and l:find("%[Target: ([^%]]+)%s?%]") then
    Toggles.fighting = true
    PromptFlags.Target = true
  end
  local forms = l:match("^%[Pl: [%d,]+ | [^%]]+%]%s?(.*)$")
  if forms or l:match("^%[Pl: [%d,]+ | [^%]]+%]$") then return prompt(forms) end

  if l:sub(1, 18) == "*** PRESS RETURN: " then
    send("\n\n"); send("score"); send("learn")
    return
  end
  if learn.watch_no_target then
    local who = l:match("^(%w+ %w+ %w+) who%?$") or l:match("^(%w+ %w+) who%?$") or l:match("^(%w+) who%?$")
    if who then return learn:find_target(who) end
  end
  if l:find("Maybe you should land first!", 1, true) then return learn:land() end
  if l:find("You lack sufficient god ki to use that technique!", 1, true) then return learn:out_of_god_ki() end

  local skill = l:match("^You have learned (.+)!") or l:match("^You've learned the skill '(.+)' from .+%.")
  if skill then Player.Skills.Learned[API.Skills:translate(skill)] = true; return end
  skill = l:match("^You have mastered the (.+) technique!")
  if skill then Player.Skills.Mastered[API.Skills:translate(skill)] = true end
end

-- (re)connecting forgets a half-read sheet
if type(registerNamedEventHandler) == "function" then
  registerNamedEventHandler("Autolearn", "AL:LinesReset", "sysConnectionEvent", function()
    L.scoreLeft, L.learnLeft, L.prev = 0, 0, nil
  end)
end
