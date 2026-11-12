-- Gogeta: Kami's timeline portal, on a loop. Type `gog help`.
--
-- Each round: pursue Kami, say yes (he takes an Essence from a Dying Star and a Celestial Diamond),
-- wait for SSJ4 Goku and SSJ4 Vegeta to land, pursue and kill both, then pursue and kill
-- Gogeta (SSJ to SSJ4) and go back to Kami.
gog = gog or {}
local G = gog

-- ---------------------------------------------------------------- settings
G.attack     = G.attack or "de"   -- attack used on every boss: "<attack> <target>" (de = death beam)
G.kamiWait   = G.kamiWait or 15   -- seconds for Kami to take the items after `say yes`
G.spawnWait  = G.spawnWait or 30  -- seconds for Goku and Vegeta to land
G.fightWait  = G.fightWait or 180 -- seconds without a kill before giving up on a fight
G.retries    = G.retries or 5     -- pursue retries when there is no ki to sense yet

-- ---------------------------------------------------------------- state
G.active  = G.active or false
G.phase   = G.phase or nil   -- kami, summon, spawn, goku, fight, gogeta, hunt
G.rounds  = G.rounds or 0
G.limit   = G.limit or nil
local timer, tries

local function info(color, msg) cecho("\n<" .. color .. ">[gog] " .. msg .. "\n") end

local function clearTimer() if timer then killTimer(timer); timer = nil end end
local function deadline(secs, why)
  clearTimer()
  timer = tempTimer(secs, function() timer = nil; G.stop("timed out " .. why) end)
end

local function hit(target) send(G.attack .. " " .. target) end

function G.stop(why)
  clearTimer()
  local was = G.active
  G.active, G.phase = false, nil
  if was then info(why and "red" or "yellow", "Stopped" .. (why and (": " .. why) or "") .. " (" .. G.rounds .. " rounds done)") end
end

-- ---------------------------------------------------------------- the round
function G.toKami()
  if not G.active then return end
  G.phase, tries = "kami", 0
  G.goku, G.vegeta = false, false
  send("pursue kami")
  deadline(60, "reaching Kami")
end

-- Pursue arrived (name) or we were already there (nil)
function G.arrived(name)
  if not G.active then return end
  local who = (name or ""):lower()
  if G.phase == "kami" and (name == nil or who:find("kami")) then
    G.phase = "summon"
    send("say yes")
    deadline(G.kamiWait, "waiting for Kami to take the Essence and the Diamond (out of them?)")
  elseif G.phase == "goku" and (name == nil or who:find("goku")) then
    G.phase = "fight"
    hit("goku")
    deadline(G.fightWait, "fighting Goku and Vegeta")
  elseif G.phase == "hunt" and (name == nil or who:find("gogeta")) then
    G.phase = "gogeta"
    hit("gogeta")
    deadline(G.fightWait, "fighting Gogeta")
  end
end

-- "Vorricer hands over the Essence from a Dying Star and the Celestial Diamond to Kami"
function G.paid()
  if not G.active or G.phase ~= "summon" then return end
  G.phase = "spawn"
  deadline(G.spawnWait, "waiting for Goku and Vegeta to land")
end

-- "[Quest: SSJ4 Vegeta] What a waste of my time...": both have landed
function G.landed()
  if not G.active or (G.phase ~= "spawn" and G.phase ~= "summon") then return end
  G.phase, tries = "goku", 0
  send("pursue goku")
  deadline(60, "reaching Goku")
end

-- "You sense no ki." while pursuing: try again shortly
function G.noKi()
  if not G.active then return end
  local target = ({ kami = "kami", goku = "goku", hunt = "gogeta" })[G.phase]
  if not target then return end
  tries = (tries or 0) + 1
  if tries > G.retries then return G.stop("can't sense " .. target) end
  tempTimer(3, function() if G.active and G.phase and ({ kami = 1, goku = 1, hunt = 1 })[G.phase] then send("pursue " .. target) end end)
end

function G.dead(who)
  if not G.active then return end
  if who == "SSJ4 Goku" or who == "SSJ4 Vegeta" then
    if who == "SSJ4 Goku" then G.goku = true else G.vegeta = true end
    if G.phase ~= "fight" then return end
    deadline(G.fightWait, "fighting Goku and Vegeta")
    if G.goku and not G.vegeta then hit("vegeta")
    elseif G.vegeta and not G.goku then hit("goku") end
  elseif who == "SSJ4 Gogeta" then
    G.rounds = G.rounds + 1
    info("green", "Gogeta down: round " .. G.rounds .. (G.limit and (" of " .. G.limit) or ""))
    if G.limit and G.rounds >= G.limit then return G.stop() end
    clearTimer()
    G.phase = "back"
    tempTimer(2, G.toKami)
  end
end

-- "When the light fades, standing before you is SSJ Gogeta!" (he may wander off: pursue him)
function G.fused()
  if not G.active then return end
  G.phase, tries = "hunt", 0
  deadline(60, "reaching Gogeta")
  tempTimer(1, function() if G.active and G.phase == "hunt" then send("pursue gogeta") end end)
end

-- ---------------------------------------------------------------- `gog` alias
G.HELP = {
  { "gog start [n]",    "Loop: Kami, Goku and Vegeta, Gogeta. Stops after n rounds if given" },
  { "gog stop",         "Stop after whatever is happening now" },
  { "gog attack <cmd>", "Attack used on the bosses (now: " .. G.attack .. ")" },
  { "gog status",       "Phase and rounds done" },
}

function G.help()
  cecho("\n<cyan>Gogeta, Kami's timeline portal on a loop:\n")
  for _, h in ipairs(G.HELP) do cecho(("  <yellow>%-18s<white>%s\n"):format(h[1], h[2])) end
  cecho("  <grey>Each round uses one Essence from a Dying Star and one Celestial Diamond Gemstone.\n")
end

function G.command(c, arg)
  if c == nil or c == "help" then G.help()
  elseif c == "start" then
    local n = tonumber(arg)
    if arg and not n then return info("yellow", "gog start [rounds]") end
    G.active, G.rounds, G.limit = true, 0, n
    info("green", "Started" .. (n and (" for " .. n .. " rounds") or "") .. ". gog stop stops.")
    G.toKami()
  elseif c == "stop" then
    if not G.active then return info("yellow", "Not running") end
    G.stop()
  elseif c == "attack" and arg then G.attack = arg; info("white", "Attack set to '" .. arg .. "'")
  elseif c == "status" then
    info("white", (G.active and ("Running, phase " .. tostring(G.phase)) or "Off") .. ", " .. G.rounds .. " rounds"
      .. (G.limit and (" of " .. G.limit) or "") .. ", attack '" .. G.attack .. "'")
  else info("yellow", "Unknown command. Type gog help") end
end
