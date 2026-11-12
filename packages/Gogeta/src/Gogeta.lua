-- Gogeta: Kami's timeline portal, on a loop. Type `gog help`.
--
-- Each round: pursue Kami, say yes (he takes an Essence from a Dying Star and a Celestial Diamond),
-- wait for SSJ4 Goku and SSJ4 Vegeta to land, pursue and kill both, then kill Gogeta (SSJ to SSJ4)
-- and go back to Kami. Bosses seen walking off are sensed; a rival that jumps
-- you is fought first, then the round picks up where it was.
gog = gog or {}
local G = gog

-- ---------------------------------------------------------------- settings
G.attack     = G.attack or "de"   -- attack used on every boss and rival: "<attack> <target>" (de = death beam)
G.kamiWait   = G.kamiWait or 15   -- seconds for Kami to take the items after `say yes`
G.spawnWait  = G.spawnWait or 30  -- seconds for Goku and Vegeta to land
G.fightWait  = G.fightWait or 180 -- seconds without a kill before giving up on a fight
G.rivalWait  = G.rivalWait or 600 -- seconds without a rival dying before giving up on it and carrying on
G.rivalHit   = G.rivalHit or 15   -- seconds between attacks on a rival (strong ones, nemeses, take a while)
G.minPl      = G.minPl or 80      -- % powerlevel to recover to after a rival before going on
G.healWait   = G.healWait or 120  -- seconds to wait for that at most
G.retries    = G.retries or 5     -- sense / pursue retries

-- ---------------------------------------------------------------- state
G.active  = G.active or false
G.phase   = G.phase or nil   -- kami, summon, spawn, goku, fight, hunt, gogeta, chase, back
G.rounds  = G.rounds or 0
G.limit   = G.limit or nil
G.rivals  = G.rivals or {}   -- rivals fighting me: first word (lowercase) -> name
G.mats    = G.mats or {}     -- { essence = n, diamond = n } from the last count
G.pl      = G.pl or nil      -- powerlevel %, from the prompt
local timer, tries

local function info(color, msg) cecho("\n<" .. color .. ">[gog] " .. msg .. "\n") end
local function fighting() return next(G.rivals) ~= nil end

local function clearTimer() if timer then killTimer(timer); timer = nil end end
local function deadline(secs, why)
  clearTimer()
  timer = tempTimer(secs, function() timer = nil; G.stop("timed out " .. why) end)
end

local function hit(target) send(G.attack .. " " .. target) end

function G.stop(why)
  clearTimer()
  local was = G.active
  G.active, G.phase, G.rivals = false, nil, {}
  if was then info(why and "red" or "yellow", "Stopped" .. (why and (": " .. why) or "") .. " (" .. G.rounds .. " rounds done)") end
end

-- ---------------------------------------------------------------- getting there
-- Far away (just landed, or after a rival): `pursue`. Seen leaving or flying off nearby: `sense`.
-- If the concentration slips, sense again; if they can't be sensed from here, pursue them.
function G.travel(target, how)
  G.target, G.how, tries = target, how or "pursue", 0
  if fighting() then return end
  send(G.how .. " " .. target)
  deadline(60, "reaching " .. target)
end

-- "You lose your concentration."
function G.senseSlipped()
  if not G.active or not G.target or fighting() then return end
  tries = (tries or 0) + 1
  if tries > G.retries then return G.stop("couldn't sense " .. G.target) end
  tempTimer(1, function() if G.active and G.target and not fighting() then send("sense " .. G.target) end end)
end

-- "You can't seem to sense SSJ4 Goku's ki from here."
function G.cantSense()
  if not G.active or not G.target or fighting() then return end
  send("pursue " .. G.target)
end

-- "You sense no ki." (pursue): try again shortly
function G.noKi()
  if not G.active or fighting() then return end
  local target = G.phase == "kami" and "kami" or G.target
  if not target then return end
  tries = (tries or 0) + 1
  if tries > G.retries then return G.stop("can't sense " .. target) end
  tempTimer(3, function()
    if G.active and not fighting() then send((G.phase == "kami" and "pursue " or (G.how or "pursue") .. " ") .. target) end
  end)
end

-- ---------------------------------------------------------------- the round
function G.toKami()
  if not G.active then return end
  G.phase, G.target, tries = "kami", nil, 0
  G.goku, G.vegeta = false, false
  if fighting() then return end
  send("pursue kami")
  deadline(90, "reaching Kami")
end

-- Arrived: pursue's "tracked down <name>", sense's "concentrate and sense <name>'s ki", or same room (nil)
function G.arrived(name)
  if not G.active or fighting() then return end
  local who = (name or ""):lower()
  local function is(k) return name == nil or who:find(k, 1, true) end
  if G.phase == "kami" and is("kami") then
    G.phase = "summon"
    send("say yes")
    deadline(G.kamiWait, "waiting for Kami to take the Essence and the Diamond (out of them?)")
  elseif G.phase == "goku" and is("goku") then
    G.phase, G.target = "fight", nil
    hit("goku")
    deadline(G.fightWait, "fighting Goku and Vegeta")
  elseif G.phase == "hunt" and is("gogeta") then
    G.phase, G.target = "gogeta", nil
    hit("gogeta")
    deadline(G.fightWait, "fighting Gogeta")
  elseif G.phase == "chase" and G.target and is(G.target) then
    G.phase = G.after
    hit(G.target)
    G.target = nil
    deadline(G.fightWait, "fighting after a chase")
  end
end

-- "Vorricer hands over the Essence from a Dying Star and the Celestial Diamond to Kami"
function G.paid()
  if not G.active or G.phase ~= "summon" then return end
  G.phase = "spawn"
  G.mats.essence = G.mats.essence and math.max(G.mats.essence - 1, 0)
  G.mats.diamond = G.mats.diamond and math.max(G.mats.diamond - 1, 0)
  if not fighting() then deadline(G.spawnWait, "waiting for Goku and Vegeta to land") end
end

-- "[Quest: SSJ4 Vegeta] What a waste of my time...": both have landed
function G.landed()
  if not G.active or (G.phase ~= "spawn" and G.phase ~= "summon") then return end
  G.phase = "goku"
  G.travel("goku")
end

function G.dead(who)
  if not G.active then return end
  if who == "SSJ4 Goku" or who == "SSJ4 Vegeta" then
    if who == "SSJ4 Goku" then G.goku = true else G.vegeta = true end
    if G.phase ~= "fight" or fighting() then return end
    deadline(G.fightWait, "fighting Goku and Vegeta")
    if G.goku and not G.vegeta then hit("vegeta")
    elseif G.vegeta and not G.goku then hit("goku") end
  elseif who == "SSJ4 Gogeta" then
    G.rounds = G.rounds + 1
    local left = G.mats.essence and G.mats.diamond and math.min(G.mats.essence, G.mats.diamond)
    info("green", "Gogeta down: round " .. G.rounds .. (G.limit and (" of " .. G.limit) or "")
      .. (left and (" (" .. G.mats.essence .. " Essences, " .. G.mats.diamond .. " Diamonds left)") or ""))
    clearTimer()
    if G.limit and G.rounds >= G.limit then return G.stop() end
    if left == 0 then return G.stop("out of " .. (G.mats.essence == 0 and "Essences" or "Diamonds")) end
    G.phase = "back"
    tempTimer(2, function() if G.active and G.phase == "back" then G.toKami() end end)
  end
end

-- "When the light fades, standing before you is SSJ Gogeta!": he's right here (if he walks off, `moved` senses him)
function G.fused()
  if not G.active then return end
  G.phase = "gogeta"
  deadline(G.fightWait, "fighting Gogeta")
  tempTimer(1, function() if G.active and G.phase == "gogeta" and not fighting() then hit("gogeta") end end)
end

-- "SSJ Gogeta leaves south." / "SSJ4 Goku flies west.": sense them again and keep hitting
function G.moved(name)
  if not G.active or fighting() then return end
  local low = name:lower()
  local kw = low:find("gogeta") and "gogeta" or low:find("goku") and "goku" or low:find("vegeta") and "vegeta"
  if not kw then return end
  if G.phase == "fight" and kw ~= "gogeta" and not G[kw] then G.after = "fight"
  elseif G.phase == "gogeta" and kw == "gogeta" then G.after = "gogeta"
  else return end
  G.phase = "chase"
  tempTimer(1, function() if G.active and G.phase == "chase" then G.travel(kw, "sense") end end)
end

-- "SSJ4 Gogeta drops SSJ4 Gogeta's explosive red aura (Celestial).": pick up Celestial drops only,
-- by the last word of the name ("aura"). Legendary and plain drops stay on the ground.
function G.keyword(item)
  item = item:gsub("%s*%b()", "")
  return item:match("(%w+)%s*$")
end
function G.dropped(item)
  if not G.active then return end
  local kw = G.keyword(item)
  if not kw then return end
  info("magenta", "Celestial drop: " .. item)
  send("get " .. kw:lower())
end

-- ---------------------------------------------------------------- rivals
-- Rivals can be strong (a nemesis takes a while): keep hitting one every G.rivalHit seconds until
-- it's dead, sense it if it moves away, then recover before going back to the round.
local rivalGen = 0
local function firstRival() for k in pairs(G.rivals) do return k end end

local function hitRivals()
  rivalGen = rivalGen + 1
  local gen = rivalGen
  local function again()
    if not G.active or gen ~= rivalGen or not fighting() then return end
    hit(firstRival())
    tempTimer(G.rivalHit, again)
  end
  again()
end

-- "The sky splits open as Chillix the Icer crashes down upon you, ..." / "... flies out of nowhere and attacks you!"
function G.rivalAppears(name, victim)
  if not G.active or (victim or ""):lower() ~= "you" then return end
  local key = name:match("^(%S+)"):lower()
  local new = not G.rivals[key]
  G.rivals[key] = name
  info("red", "Rival " .. name .. ": fighting it first")
  if new then hitRivals() end
  clearTimer()
  timer = tempTimer(G.rivalWait, function()
    timer = nil
    info("yellow", "No rival died in " .. G.rivalWait .. "s: carrying on with the round")
    G.rivals = {}
    G.whenHealthy(G.resume)
  end)
end

-- "Death Beam who?": the rival moved away, sense it
local lastWho = 0
function G.noTarget()
  if not G.active or not fighting() then return end
  local now = os.time()
  if now - lastWho < 5 then return end
  lastWho = now
  send("sense " .. firstRival())
end

-- "Chillix the Icer is dead!  R.I.P.": once every rival is down, recover, then carry on from where the round was
function G.rivalDead(name)
  local key = (name:match("^(%S+)") or ""):lower()
  if not G.active or not G.rivals[key] then return end
  G.rivals[key] = nil
  if fighting() then return end
  clearTimer()
  info("green", "Rival down, back to the round")
  tempTimer(2, function() if G.active and not fighting() then G.whenHealthy(G.resume) end end)
end

-- The prompt's "[Pl: 151,520,583,583 99% | ..."
function G.prompt(pct) G.pl = tonumber(pct) end

-- Wait (at most G.healWait seconds) until the powerlevel is back to G.minPl %
function G.whenHealthy(fn)
  local waited = 0
  local function check()
    if not G.active or fighting() then return end
    if not G.pl or G.pl >= G.minPl or waited >= G.healWait then return fn() end
    if waited == 0 then info("yellow", "Recovering first (powerlevel " .. G.pl .. "%)") end
    waited = waited + 3
    tempTimer(3, check)
  end
  check()
end

-- "You are dead!"
function G.died()
  if G.active then G.stop("you died") end
end

function G.resume()
  local p = G.phase
  if p == "kami" or p == "summon" or p == "back" or p == nil then G.toKami()
  elseif p == "spawn" then deadline(G.spawnWait, "waiting for Goku and Vegeta to land")
  elseif p == "goku" then G.travel("goku")
  elseif p == "fight" then
    if G.goku and G.vegeta then return end   -- fusing: the fused line moves on
    G.phase, G.after = "chase", "fight"
    G.travel(G.goku and "vegeta" or "goku")
  elseif p == "hunt" or p == "gogeta" then G.phase = "hunt"; G.travel("gogeta")
  elseif p == "chase" then G.travel(G.target or "gogeta") end   -- after a rival they may be far: pursue
end

-- ---------------------------------------------------------------- materials
-- `inventory` lists "(19) Essence from a Dying Star", `materials` "(19) a Celestial Diamond Gemstone (Tier 6)".
-- Both end with "To see additional inventory use:".
function G.count(done)
  G.counting = { essence = 0, diamond = 0, ends = 0, done = done }
  send("inventory")
  send("materials")
  G.counting.timer = tempTimer(8, function()
    local c = G.counting
    G.counting = nil
    if c then info("red", "Couldn't read inventory and materials"); if c.done then c.done(nil) end end
  end)
end

function G.countItem(kind, n)
  if G.counting then G.counting[kind] = G.counting[kind] + (tonumber(n) or 1) end
end

function G.countEnd()
  local c = G.counting
  if not c then return end
  c.ends = c.ends + 1
  if c.ends < 2 then return end
  killTimer(c.timer)
  G.counting = nil
  G.mats = { essence = c.essence, diamond = c.diamond }
  local rounds = math.min(c.essence, c.diamond)
  info(rounds > 0 and "white" or "red", ("Materials: %d Essence%s from a Dying Star, %d Celestial Diamond%s: %d round%s"):format(
    c.essence, c.essence == 1 and "" or "s", c.diamond, c.diamond == 1 and "" or "s", rounds, rounds == 1 and "" or "s"))
  if c.done then c.done(rounds) end
end

-- ---------------------------------------------------------------- buying Essences
-- `gog buy <n>`: read `eshop` for the Essence's number and price (they change with the events),
-- then `eshop buy <#>` n times, no more than the event points cover.
G.shop = G.shop or {}
function G.buy(n)
  G.shop = { want = n }
  send("eshop")
  G.shop.timer = tempTimer(8, function()
    if G.shop.want then info("red", "Couldn't read the event shop"); G.shop = {} end
  end)
end

-- "(19)  500           Essence from a Dying Star"
function G.shopItem(num, cost)
  if not G.shop.want then return end
  G.shop.num, G.shop.cost = tonumber(num), tonumber(cost)
end

-- " You currently have 251,468 event points."
function G.shopPoints(points)
  local sh = G.shop
  if not sh.want then return end
  if sh.timer then killTimer(sh.timer) end
  G.shop = {}
  if not sh.num then return info("red", "No Essence from a Dying Star in the event shop right now") end
  local have = tonumber((points:gsub(",", ""))) or 0
  local n = math.min(sh.want, math.floor(have / sh.cost))
  if n < 1 then return info("red", ("Not enough event points: an Essence costs %d, you have %d"):format(sh.cost, have)) end
  info("green", ("Buying %d Essence%s from a Dying Star (#%d, %d each, %d of %d points)%s"):format(
    n, n == 1 and "" or "s", sh.num, sh.cost, n * sh.cost, have, n < sh.want and " - all you can afford" or ""))
  G.buying = { want = n, got = 0 }
  for i = 1, n do tempTimer((i - 1) * 0.3, function() send("eshop buy " .. sh.num) end) end
  tempTimer((n - 1) * 0.3 + 4, function()
    local b = G.buying
    G.buying = nil
    if not b then return end
    if b.got == b.want then info("green", ("Bought %d Essence%s"):format(b.got, b.got == 1 and "" or "s"))
    else info("red", ("Only %d of %d Essences were bought - check the shop's replies"):format(b.got, b.want)) end
  end)
end

-- "You spend 500 epoints for Essence from a Dying Star."
function G.spent()
  if G.buying then G.buying.got = G.buying.got + 1 end
end

-- ---------------------------------------------------------------- `gog` alias
G.HELP = {
  { "gog start [n]",    "Count materials, then loop: Kami, Goku and Vegeta, Gogeta (n rounds at most)" },
  { "gog stop",         "Stop after whatever is happening now" },
  { "gog attack <cmd>", "Attack used on the bosses (now: " .. G.attack .. ")" },
  { "gog status",       "Phase and rounds done" },
  { "gog resume",       "Forget the rivals being fought and carry on with the round" },
  { "gog check",        "Count your Essences and Diamonds (how many rounds you can run)" },
  { "gog buy <n>",      "Buy n Essences from a Dying Star from the event shop (finds its number in eshop)" },
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
    if G.active then return info("yellow", "Already running. gog stop first") end
    G.count(function(rounds)
      if rounds == 0 then return info("red", "Nothing to give Kami: not started") end
      G.active, G.rounds, G.rivals = true, 0, {}
      G.limit = (n and rounds) and math.min(n, rounds) or n or rounds
      info("green", "Started for " .. (G.limit and (G.limit .. " rounds") or "as long as it lasts") .. ". gog stop stops.")
      G.toKami()
    end)
  elseif c == "check" then G.count()
  elseif c == "resume" then
    if not G.active then return info("yellow", "Not running") end
    G.rivals = {}; clearTimer(); info("white", "Carrying on with the round"); G.resume()
  elseif c == "stop" then
    if not G.active then return info("yellow", "Not running") end
    G.stop()
  elseif c == "buy" then
    local n = tonumber(arg)
    if not n or n < 1 then return info("yellow", "gog buy <how many>") end
    G.buy(math.floor(n))
  elseif c == "attack" and arg then G.attack = arg; info("white", "Attack set to '" .. arg .. "'")
  elseif c == "status" then
    info("white", (G.active and ("Running, phase " .. tostring(G.phase) .. (fighting() and " (fighting a rival)" or "")) or "Off") .. ", " .. G.rounds .. " rounds"
      .. (G.limit and (" of " .. G.limit) or "") .. ", attack '" .. G.attack .. "'")
  else info("yellow", "Unknown command. Type gog help") end
end
