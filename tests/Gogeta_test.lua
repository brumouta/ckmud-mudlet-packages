-- gog: the Kami / Goku and Vegeta / Gogeta loop, driven by lines from real rounds.
-- Run from the repo root: lua tests/Gogeta_test.lua
local now, timers, id, sent = 0, {}, 0, {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(d, f) id = id + 1; timers[id] = { at = now + d, f = f }; return id end
function killTimer(i) if i then timers[i] = nil end end
local function wait(s)
  local target = now + s
  while true do
    local best, bi
    for i, t in pairs(timers) do if t.at <= target and (not best or t.at < best.at) then best, bi = t, i end end
    if not best then break end
    timers[bi] = nil; now = best.at; best.f()
  end
  now = target
end
local function ok(c, what) assert(c, what); print("OK  " .. what) end
local function expect(want)
  local got = table.concat(sent, " | "); sent = {}
  assert(got == want, "\n got: " .. got .. "\nwant: " .. want); print("OK  " .. (want == "" and "(nothing)" or want))
end

dofile("packages/Gogeta/src/Gogeta.lua")
-- The package.json triggers, as Lua patterns
local TRIG = {
  { "^You have successfully tracked down (.+)!$", function(m) gog.arrived(m) end },
  { "You're already in the same room!!", function() gog.arrived(nil) end, plain = true },
  { "You sense no ki.", function() gog.noKi() end, plain = true },
  { "hands over the Essence from a Dying Star and the Celestial Diamond to Kami", function() gog.paid() end, plain = true },
  { "[Quest: SSJ4 Vegeta] What a waste of my time", function() gog.landed() end, plain = true },
  { "standing before you is SSJ Gogeta!", function() gog.fused() end, plain = true },
  { "^SSJ4 %a+ drops (.-) %(Celestial%)%.?$", function(m) gog.dropped(m) end },
  { "^%(%s*(%d+)%)%s+(%d+)%s+Essence from a Dying Star%s*$", function(a, b) gog.shopItem(a, b) end, two = true },
  { "You currently have ([%d,]+) event points%.", function(m) gog.shopPoints(m) end },
  { "^You spend %d+ epoints for Essence from a Dying Star%.$", function() gog.spent() end },
  { "^(SSJ4 [GV]%a+) is dead!%s+R%.I%.P%.", function(m) if m == "SSJ4 Goku" or m == "SSJ4 Vegeta" or m == "SSJ4 Gogeta" then gog.dead(m) end end },
}
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    for _, t in ipairs(TRIG) do
      if t.plain then if l:find(t[1], 1, true) then t[2]() end
      else local m, m2 = l:match(t[1]); if m then t[2](m, m2) end end
    end
  end
end

local KAMI = "You have successfully tracked down Kami, Earth's Guardian!"
local PAID = "Vorricer hands over the Essence from a Dying Star and the Celestial Diamond to Kami, Earth's Guardian."
local LANDED = [[[Quest: SSJ4 Goku] I still want to see for myself just how powerful they really are! Come on Vegeta, lets see what they are capable of!
[Quest: SSJ4 Vegeta] What a waste of my time, very well, lets play this little game of yours.]]
local GOKU = "You have successfully tracked down SSJ4 Goku!"
local FUSE = "When the light fades, standing before you is SSJ Gogeta!"

-- Round 1: Goku dies first, then Vegeta (whose death line comes after the fusion)
assert(gog.attack == "de")
gog.command("start", "3")
expect("pursue kami")
feed(KAMI); expect("say yes")
feed(PAID); feed(LANDED); expect("pursue goku")
feed(GOKU); expect("de goku")
feed("SSJ4 Goku is dead!  R.I.P."); expect("de vegeta")
feed(FUSE .. "\nSSJ4 Vegeta is dead!  R.I.P."); expect("")
wait(1); expect("pursue gogeta")
feed("You're already in the same room!!"); expect("de gogeta")
feed("SSJ Gogeta's aura grows larger\nSSJ4 Gogeta is dead!  R.I.P."); expect("")
ok(gog.rounds == 1, "round 1 counted")
wait(2); expect("pursue kami")

-- Round 2: a counter kills Vegeta first, then Goku; Gogeta wanders off south
feed(KAMI); feed(PAID); feed(LANDED); expect("say yes | pursue goku")
feed(GOKU); expect("de goku")
feed("SSJ4 Vegeta is dead!  R.I.P."); expect("de goku")
feed(FUSE .. "\nSSJ4 Goku is dead!  R.I.P."); expect("")
wait(1); expect("pursue gogeta")
feed("SSJ Gogeta leaves south.\nYou have successfully tracked down SSJ Gogeta!"); expect("de gogeta")
feed("SSJ4 Gogeta is dead!  R.I.P."); wait(2); expect("pursue kami")

-- Round 3 ends the run (limit 3)
feed("You're already in the same room!!"); expect("say yes")
feed(PAID); feed(LANDED); feed(GOKU); feed("SSJ4 Goku is dead!  R.I.P."); feed(FUSE); wait(1)
feed("You're already in the same room!!"); feed("SSJ4 Gogeta is dead!  R.I.P."); wait(5)
expect("pursue goku | de goku | de vegeta | pursue gogeta | de gogeta")
ok(not gog.active and gog.rounds == 3, "stops after 3 rounds")

-- Celestial drops are picked up, Legendary and plain ones aren't
gog.command("start"); sent = {}
feed("SSJ4 Gogeta drops SSJ4 Gogeta's explosive red aura (Legendary).\nSSJ4 Gogeta drops Celestial Knights Legendary Loot Box.\nSSJ4 Goku drops SSJ4 Goku's Halo.")
expect("")
feed("SSJ4 Gogeta drops SSJ4 Gogeta's explosive red aura (Celestial).\nSSJ4 Goku drops SSJ4 Goku's Tail (Celestial).")
expect("get aura | get tail")
gog.command("stop"); sent = {}

-- Out of items: Kami never takes them -> stop
gog.command("start"); expect("pursue kami")
feed(KAMI); expect("say yes")
wait(gog.kamiWait + 1)
ok(not gog.active and LOG:find("out of them"), "stops when Kami doesn't take the items")

-- Goku not landed yet: retry the pursue
gog.command("start"); feed(KAMI); feed(PAID); feed(LANDED); sent = {}
feed("You sense no ki."); wait(3); expect("pursue goku")
gog.command("stop"); ok(not gog.active, "gog stop")
-- not running: lines do nothing
feed(KAMI .. "\n" .. GOKU .. "\nSSJ4 Goku is dead!  R.I.P."); expect("")
-- Buying Essences: the number comes from the listing, capped by the points
local SHOP = [[ Event Shop:
o------------------------------------------------------------o
  #   Cost         Item Description
o------------------------------------------------------------o
( 1)  500000        a Hyperbolic Coupon
(16)  1000          an Unstable Makai Shard
(19)  500           Essence from a Dying Star
(20)  50            Dragonball Token
o------------------------------------------------------------o
 Syntax: eshop  'buy/detail' <item #> [legend/celestial]
        Legendary/Celestial Items cost 2.5x/5x More
 You currently have 251,468 event points.]]
sent = {}
local BOUGHT = "You spend 500 epoints for Essence from a Dying Star."
gog.command("buy", "3"); expect("eshop")
feed(SHOP); wait(1); expect("eshop buy 19 | eshop buy 19 | eshop buy 19")
feed(BOUGHT .. "\n" .. BOUGHT .. "\n" .. BOUGHT); wait(5)
ok(LOG:find("Bought 3 Essences"), "every purchase confirmed")
gog.command("buy", "2"); feed(SHOP); wait(1); sent = {}
feed(BOUGHT); wait(5)
ok(LOG:find("Only 1 of 2 Essences were bought"), "a purchase without its reply is reported")
gog.command("buy", "10"); sent = {}
feed((SHOP:gsub("251,468", "1,200"))); wait(5); expect("eshop buy 19 | eshop buy 19")
ok(LOG:find("all you can afford"), "capped by the event points")
gog.command("buy", "1"); sent = {}
feed((SHOP:gsub("%(19%)%s+500%s+Essence from a Dying Star\n", ""))); wait(1); expect("")
ok(LOG:find("No Essence from a Dying Star"), "no Essence in the shop: buys nothing")
feed(SHOP); wait(1); expect("")   -- a later eshop by hand buys nothing
print("gog: ALL PASSED")
