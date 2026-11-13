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
gog.needBuffs = false   -- the zenni buff checks have their own tests at the end
-- The package.json triggers, as Lua patterns
local TRIG = {
  { "^You have successfully tracked down (.+)!$", function(m) gog.arrived(m) end },
  { "^You concentrate and sense (.+)'s ki%.$", function(m) gog.arrived(m) end },
  { "You're already in the same room!!", function() gog.arrived(nil) end, plain = true },
  { "^You lose your concentration%.$", function() gog.senseSlipped() end },
  { "^You can't seem to sense (.+)'s ki from here%.$", function() gog.cantSense() end },
  { "You sense no ki.", function() gog.noKi() end, plain = true },
  { "hands over the Essence from a Dying Star and the Celestial Diamond to Kami", function() gog.paid() end, plain = true },
  { "[Quest: SSJ4 Vegeta] What a waste of my time", function() gog.landed() end, plain = true },
  { "standing before you is SSJ Gogeta!", function() gog.fused() end, plain = true },
  { "^(SSJ%d? %a+) leaves %a+%.$", function(m) gog.moved(m) end },
  { "^(SSJ%d? %a+) flies %a+%.$", function(m) gog.moved(m) end },
  { "^SSJ4 %a+ drops (.-) %(Celestial%)%.?$", function(m) gog.dropped(m) end },
  { "^(SSJ4 [GV]%a+) is dead!%s+R%.I%.P%.", function(m) if m == "SSJ4 Goku" or m == "SSJ4 Vegeta" or m == "SSJ4 Gogeta" then gog.dead(m) end end },
  { "^The sky splits open as (.-) crashes down upon (%w+), wreathed in a blazing aura!$", function(a, b) gog.rivalAppears(a, b) end },
  { "^(.-) flies out of nowhere and attacks (%w+)!$", function(a, b) gog.rivalAppears(a, b) end },
  { "^(.-) is dead!%s+R%.I%.P%.", function(m) gog.rivalDead(m) end },
  { "^[%w ]+ who%?$", function() gog.noTarget() end },
  { "^%[Pl: [%d,]+ (%d+)%% ", function(m, _, l) gog.prompt(m, l) end },
  { "Lacking God Ki, you lose your heightened ultra state", function() gog.uiLost() end, plain = true },
  { "^%s*You have (.-) remaining on [%d.]+x Zenni Boost", function(m) gog.buffLine("boost", m) end },
  { "^Your zenni boost will expire in (.-)!", function(m) gog.buffLine("boost", m) end },
  { "^%s*Temp: Zenni%s*:.* for (.-)%.?$", function(m) gog.buffLine("temp", m) end },
  { "^%s*%[Ki Tab Bonus%]", function() gog.statusEnd() end },
  { "^You are dead!", function() gog.died() end },
  { "^%((%s*%d+)%) Essence from a Dying Star$", function(m) gog.countItem("essence", m) end },
  { "^Essence from a Dying Star$", function() gog.countItem("essence", "") end },
  { "^%((%s*%d+)%) a Celestial Diamond Gemstone", function(m) gog.countItem("diamond", m) end },
  { "^a Celestial Diamond Gemstone", function() gog.countItem("diamond", "") end },
  { "^To see additional inventory use:", function() gog.countEnd() end },
  { "^%(%s*(%d+)%)%s+(%d+)%s+Essence from a Dying Star%s*$", function(a, b) gog.shopItem(a, b) end },
  { "You currently have ([%d,]+) event points%.", function(m) gog.shopPoints(m) end },
  { "^You spend %d+ epoints for Essence from a Dying Star%.$", function() gog.spent() end },
}
local function feed(text)
  for l in (text .. "\n"):gmatch("(.-)\n") do
    for _, t in ipairs(TRIG) do
      if t.plain then if l:find(t[1], 1, true) then t[2]() end
      else local m, m2 = l:match(t[1]); if m then t[2](m, m2, l) end end
    end
  end
end

local KAMI = "You have successfully tracked down Kami, Earth's Guardian!"
local PAID = "Vorricer hands over the Essence from a Dying Star and the Celestial Diamond to Kami, Earth's Guardian."
local LANDED = [[[Quest: SSJ4 Goku] I still want to see for myself just how powerful they really are! Come on Vegeta, lets see what they are capable of!
[Quest: SSJ4 Vegeta] What a waste of my time, very well, lets play this little game of yours.]]
local TRACKED = "You have successfully tracked down SSJ4 Goku!"
local GOKU = "You concentrate and sense SSJ4 Goku's ki."
local GOGETA = "You concentrate and sense SSJ Gogeta's ki."
local FUSE = "When the light fades, standing before you is SSJ Gogeta!"
local function mats(e, d)
  feed("You are carrying in your Inventory:\n( 2) a return capsule to the Briefs mansion (Tier 6)\n" ..
       (e and ("(" .. e .. ") Essence from a Dying Star\n") or "") .. "To see additional inventory use:\n" ..
       "Materials you are carrying:\n( 2) some silicone polymer [300]\n" ..
       (d and ("(" .. d .. ") a Celestial Diamond Gemstone (Tier 6)\n") or "") .. "To see additional inventory use:")
end

assert(gog.attack == "de")
-- gog check: counts both
gog.command("check"); expect("inventory | materials")
mats(19, "3"); ok(gog.mats.essence == 19 and gog.mats.diamond == 3 and LOG:find("3 rounds"), "materials counted: 3 rounds")
-- nothing to give: not started
gog.command("start"); sent = {}; mats(19, nil)
ok(not gog.active and LOG:find("not started"), "no Diamonds: not started")

gog.command("start"); expect("inventory | materials")
mats(19, 3); expect("pursue kami")
ok(gog.limit == 3, "runs as many rounds as the Diamonds allow")
-- Round 1: Goku dies first, then Vegeta (whose death line comes after the fusion); Gogeta walks off
feed(KAMI); expect("say yes")
feed(PAID); feed(LANDED); expect("pursue goku")
feed(TRACKED); expect("de goku")
feed("SSJ4 Goku is dead!  R.I.P."); expect("de vegeta")
feed(FUSE .. "\nSSJ4 Vegeta is dead!  R.I.P."); expect("")
wait(1); expect("de gogeta")
feed("SSJ Gogeta leaves south."); wait(1); expect("sense gogeta")
feed("You lose your concentration."); wait(1); expect("sense gogeta")
feed(GOGETA); expect("de gogeta")
feed("SSJ Gogeta's aura grows larger\nSSJ4 Gogeta is dead!  R.I.P."); expect("")
ok(gog.rounds == 1 and LOG:find("2 Diamonds left"), "round 1 counted, materials go down")
wait(2); expect("pursue kami")

-- Round 2: Goku and Vegeta fly off before the first hit; Vegeta dies first; Gogeta flies off out of sense range
feed(KAMI); feed(PAID); feed(LANDED); expect("say yes | pursue goku")
feed(TRACKED); expect("de goku")
feed("SSJ4 Goku flies west.\nSSJ4 Vegeta flies west."); wait(1); expect("sense goku")
feed(GOKU); expect("de goku")
feed("SSJ4 Vegeta is dead!  R.I.P."); expect("de goku")
feed(FUSE .. "\nSSJ4 Goku is dead!  R.I.P."); wait(1); expect("de gogeta")
feed("SSJ Gogeta flies north."); wait(1); expect("sense gogeta")
feed("You can't seem to sense SSJ Gogeta's ki from here."); expect("pursue gogeta")
feed("You have successfully tracked down SSJ Gogeta!"); expect("de gogeta")
feed("SSJ4 Gogeta is dead!  R.I.P."); wait(2); expect("pursue kami")

-- Round 3: a rival jumps me on the way to Goku; fight it, then pursue Goku again
feed(KAMI); feed(PAID); feed(LANDED); expect("say yes | pursue goku")
feed("The sky splits open as Chillix the Icer crashes down upon you, wreathed in a blazing aura!\nYou are attacked and lose the trail!")
expect("de chillix")
feed(TRACKED); expect("")      -- arrivals wait while the rival is alive
feed("Seij flies out of nowhere and attacks Technine!"); expect("")   -- someone else's rival
feed("Chillix the Icer is dead!  R.I.P."); wait(2); expect("pursue goku")
feed(TRACKED); feed("SSJ4 Goku is dead!  R.I.P."); feed(FUSE); feed("SSJ4 Vegeta is dead!  R.I.P."); wait(1)
feed("SSJ4 Gogeta is dead!  R.I.P."); wait(5)
expect("de goku | de vegeta | de gogeta")
ok(not gog.active and gog.rounds == 3 and LOG:find("3 rounds done"), "stops when the Diamonds run out")

-- A strong rival (a nemesis): keep hitting it, sense it when it moves, recover before going on
os.time = function() return math.floor(now) end
gog.command("start", "1"); mats(5, 5); expect("inventory | materials | pursue kami")
feed(KAMI); feed(PAID); feed(LANDED); expect("say yes | pursue goku")
feed("The sky splits open as Nemesis Vorricer crashes down upon you, wreathed in a blazing aura!"); expect("de nemesis")
wait(15); expect("de nemesis")
wait(15); expect("de nemesis")
feed("Death Beam who?"); expect("sense nemesis")
feed("[Pl: 151,520,583,583 40% | Ki: 91% | Fatigue: 2%]")
feed("Nemesis Vorricer is dead!  R.I.P."); wait(2); expect("")
ok(LOG:find("Recovering first"), "low powerlevel after the rival: waits")
wait(6); expect("")
feed("[Pl: 151,520,583,583 85% | Ki: 91% | Fatigue: 2%]"); wait(3); expect("pursue goku")
wait(30); expect("")   -- no more rival attacks once it's dead
-- dying stops the loop
feed("You are dead!  You are sent to the Next Dimension.")
ok(not gog.active and LOG:find("you died"), "stops when you die")

-- A rival on the way to Kami: pursue Kami again afterwards
gog.command("start", "1"); mats(5, 5); expect("inventory | materials | pursue kami")
feed("The sky splits open as Chillix the Icer crashes down upon you, wreathed in a blazing aura!"); expect("de chillix")
feed("Chillix the Icer is dead!  R.I.P."); wait(2); expect("pursue kami")
-- Out of items: Kami never takes them -> stop
feed(KAMI); expect("say yes")
wait(gog.kamiWait + 1)
ok(not gog.active and LOG:find("out of them"), "stops when Kami doesn't take the items")

-- Celestial drops are picked up, Legendary and plain ones aren't
gog.command("start", "1"); mats(5, 5); sent = {}
feed("SSJ4 Gogeta drops SSJ4 Gogeta's explosive red aura (Legendary).\nSSJ4 Gogeta drops Celestial Knights Legendary Loot Box.\nSSJ4 Goku drops SSJ4 Goku's Halo.")
expect("")
feed("SSJ4 Gogeta drops SSJ4 Gogeta's explosive red aura (Celestial).\nSSJ4 Goku drops SSJ4 Goku's Tail (Celestial).")
expect("get aura | get tail")
gog.command("stop"); sent = {}

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

-- Super Saiyan 3 Goku answers `pursue goku` first: kill him, then pursue the SSJ4 one
gog.command("start", "1"); mats(5, 5); expect("inventory | materials | pursue kami")
feed(KAMI); feed(PAID); feed(LANDED); expect("say yes | pursue goku")
feed("You have successfully tracked down Super Saiyan 3 Goku!"); expect("de goku")
ok(gog.phase == "goku", "still after SSJ4 Goku")
feed("Super Saiyan 3 Goku is dead!  R.I.P."); wait(1); expect("pursue goku")
feed(TRACKED); expect("de goku")
gog.command("stop"); sent = {}

-- Ultra Instinct kept up while looping, as god ki allows
local P = "[Pl: 177,474,327,534 100%% | Ki: 100%% | GK: %d%% | Fatigue: 0%%] %s[FLY][1/42127x G]"
feed(P:format(30, "")); expect("")                          -- not looping: leave it alone
gog.command("start", "1"); mats(5, 5); expect("inventory | materials | pursue kami")
feed(P:format(30, "[UI] [HT] ")); expect("")
feed(P:format(30, "[TUI] [HT] ")); expect("")
feed("Lacking God Ki, you lose your heightened ultra state...")
ok(LOG:find("Ultra Instinct dropped"), "says when UI drops")
feed(P:format(1, "[HT] ")); expect("")                      -- not enough god ki yet
feed(P:format(8, "[HT] ")); expect("focus 'ultra instinct'")
feed(P:format(8, "[HT] ")); expect("")                      -- not again straight away
wait(8); feed(P:format(8, "[UI] ")); expect("")
gog.command("ui", "tui"); wait(8)
feed(P:format(8, "[UI] ")); expect("focus 'true ultra instinct'")
wait(8); feed(P:format(8, "")); expect("focus 'ultra instinct' | focus 'true ultra instinct'")
gog.command("ui", "off"); wait(8); feed(P:format(50, "")); expect("")
gog.command("ui", "ui")
-- a heal at low powerlevel, if set
gog.panicCmd = "sz"
feed("[Pl: 1 30% | Ki: 100% | GK: 50% | Fatigue: 0%] [UI] "); expect("sz")
feed("[Pl: 1 20% | Ki: 100% | GK: 50% | Fatigue: 0%] [UI] "); expect("")   -- once per 30s
gog.panicCmd = nil
gog.command("stop"); sent = {}
-- Zenni buffs: both needed to start; the farm stops between rounds once one runs out
gog.needBuffs = true
local function status(boost, temp)
  return " Status:\n  You feel Great.\n" .. (boost and ("  You have " .. boost .. " remaining on 2.0x Zenni Boost\n") or "") ..
    " Affections:\n" .. (temp and ("  Temp: Zenni      : +50% zenni gains for " .. temp .. ".\n") or "") ..
    "  Mansion: PL      : +15% PL gains for 21h 09m.\n  [Ki Tab Bonus]: 0 / 50,000"
end
ok(gog.duration("2h 04m") == 7440 and gog.duration("4 minutes") == 240 and gog.duration("1 hour") == 3600, "durations")
gog.command("start"); mats(5, 5); expect("inventory | materials | status")
feed(status(nil, "2h 04m")); expect("")
ok(not gog.active and LOG:find("the Zenni Boost is off"), "no Zenni Boost: not started")
gog.command("start"); mats(5, 5); expect("inventory | materials | status")
feed(status("4 minutes", nil)); expect("")
ok(not gog.active and LOG:find("Temp: Zenni is off"), "no Temp: Zenni: not started")
gog.command("start"); mats(5, 5); expect("inventory | materials | status")
feed(status("4 minutes", "2h 04m")); expect("pursue kami")
ok(gog.active and LOG:find("Zenni Boost 4m, Temp: Zenni 2h 4m"), "both on: started")
local function round()
  feed(KAMI); feed(PAID); feed(LANDED); feed(TRACKED); feed("SSJ4 Goku is dead!  R.I.P.")
  feed(FUSE); feed("SSJ4 Vegeta is dead!  R.I.P."); wait(1); sent = {}
  feed("SSJ4 Gogeta is dead!  R.I.P.")
end
round(); wait(2); expect("pursue kami")          -- still on
gog.buffEnd.boost = now                         -- (time passes: the 4 minutes are up)
round(); expect("status")                        -- the boost looks over: check
feed(status("30 minutes", "1h 58m")); wait(2); expect("pursue kami")   -- renewed: carry on
ok(gog.active, "a renewed boost keeps the farm going")
feed("Your zenni boost will expire in 1 minutes!")
ok(gog.buffEnd.boost == now + 60, "the expiry warning updates the boost's end")
gog.buffEnd.boost = now
round(); expect("status")
feed(status(nil, "1h 50m")); wait(2); expect("")
ok(not gog.active and LOG:find("the Zenni Boost ran out"), "stops when the boost runs out")
gog.needBuffs = false
print("gog: ALL PASSED")
