-- Tests gumshoe.xml in stand-ins for the CKMud client's plugin sandbox (Lua 5.1: no os, io.open,
-- require or load; only what the client offers) and for Mudlet. Nothing is sent anywhere.
--   lua5.1 test.lua [gumshoe.xml]
local xmlFile = arg[1] or 'gumshoe.xml'
local f = assert(io.open(xmlFile, 'rb')); local xml = f:read('*a'); f:close()
local src = assert(xml:match('<script><!%[CDATA%[(.*)%]%]></script>'), 'no script in ' .. xmlFile)
src = src:gsub('%]%]%]%]><!%[CDATA%[>', ']]>')
local realExit = os.exit

local now = 1795000000
local out, sent, timers, triggers, aliases, handlers, files, effects = {}, {}, {}, {}, {}, {}, {}, {}
local nextId = 1
local function id() nextId = nextId + 1; return nextId end
local function json(s)  -- enough JSON for the test payloads
  if s == 'true' then return true elseif s == 'false' then return false end
  if s:match('^"') then return s:sub(2, -2) end
  if tonumber(s) then return tonumber(s) end
  local t = {}
  for k, v in s:gmatch('"([%w_]+)"%s*:%s*([^,}]+)') do t[k] = json(v) end
  return t
end
local E
local function env(mudlet)
  local e = {}
  for _, k in ipairs{'unpack','assert','error','ipairs','next','pairs','pcall','select','tonumber','tostring','type','xpcall','setmetatable','getmetatable','rawget','rawset','rawequal'} do e[k] = _G[k] end
  e.string, e.math = string, math
  e.table = setmetatable({}, {__index = table})
  e._G = e
  e.io = { exists = function(p) return files[p] ~= nil end }
  e.getMudletHomeDir = function() return '/package' end
  e.table.save = function(p, v) files[p] = v end
  e.table.load = function(p, t) for k, v in pairs(files[p] or {}) do t[k] = v end end
  e.getEpoch = function() return now end
  e.send = function(t) sent[#sent + 1] = t end
  e.cecho = function(t) out[#out + 1] = t end
  e.echo = e.cecho
  e.tempTimer = function(s, fn, rep) local i = id(); timers[i] = {at = now + s, f = fn, rep = rep and s}; return i end
  e.killTimer = function(i) local had = timers[i] ~= nil; timers[i] = nil; return had end
  e.tempRegexTrigger = function(re, fn) assert(re == '^.*$', 'this test only knows ^.*$'); local i = id(); triggers[i] = fn; return i end
  e.registerAnonymousEventHandler = function(ev, fn) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], fn) end
  e.yajl = { to_value = json }
  e.mud = { send = e.send, note = e.cecho, msdp = function() return 'Tiamat' end,
    timer = e.tempTimer, tick = function(s, fn) return e.tempTimer(s, fn, true) end, cancel = e.killTimer,
    alias = function(name, fn) local i = id(); aliases[i] = {name = name, f = fn}; return i end, trigger = e.tempRegexTrigger,
    plugin = { register = function(v) effects[#effects + 1] = {'register', v}
      return { status = function(s) effects[#effects + 1] = {'status', s} end,
               configure = function(n, v2) effects[#effects + 1] = {'configure', n, v2} end,
               log = function() end,
               claim = function(r) effects[#effects + 1] = {'claim', r} end,
               release = function() effects[#effects + 1] = {'release'} end,
               snapshot = function() end } end } }
  e.killTrigger = function(i) local had = triggers[i] ~= nil; triggers[i] = nil; return had end
  e.killAlias = function(i) local had = aliases[i] ~= nil; aliases[i] = nil; return had end
  if mudlet then   -- Mudlet: real os and io, regex aliases, no mud table
    e.mud = nil
    e.getMudletVersion = function() return 4, 19, 1 end
    e.os = { time = function() return now end, date = function() return '12:00' end }
    e.io = { open = function(p) if files[p] then return {} end end }
    e.tempAlias = function(re, fn) local i = id(); aliases[i] = {regex = re, f = fn}; return i end
    e.raiseEvent = function(ev, ...) for _, fn in ipairs(handlers[ev] or {}) do fn(ev, ...) end end
  end
  return e
end
local function load_plugin(mudlet, again)
  if not again then
    out, sent, timers, triggers, aliases, handlers, effects = {}, {}, {}, {}, {}, {}, {}
    E = env(mudlet)
  end
  local chunk = assert(loadstring(src, '=gumshoe.xml'))
  setfenv(chunk, E)
  chunk()
end
local function input(text)
  local hit = false
  for _, a in pairs(aliases) do
    if a.regex then   -- the gum alias regex, as Mudlet would match it
      if text == 'gum' or text:match('^gum%s') then
        local c, rest = text:match('^gum%s+([%w_]+)%s*(.-)%s*$')
        E.matches = { text, c or '', rest or '' }; a.f(); hit = true
      end
    elseif text == a.name or text:sub(1, #a.name + 1) == a.name .. ' ' then
      E.command = text; a.f((text:sub(#a.name + 1):gsub('^%s+', ''):gsub('%s+$', ''))); hit = true
    end
  end
  if not hit then sent[#sent + 1] = text end
end
local function lineIn(text) E.line = text; for _, fn in pairs(triggers) do E.matches = {text}; fn() end end
local function event(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(name, ...) end end
local function advance(s)  -- one second at a time, so repeating timers fire as they would
  for _ = 1, s do
    now = now + 1
    local due = {}
    for i, t in pairs(timers) do if t.at <= now then due[#due + 1] = i end end
    table.sort(due)
    for _, i in ipairs(due) do local t = timers[i]; if t then if t.rep then t.at = now + t.rep else timers[i] = nil end; t.f() end end
  end
end
local function output() local s = table.concat(out, ''); out = {}; return s end
local function last(kind) for i = #effects, 1, -1 do if effects[i][1] == kind then return effects[i] end end end
local function count(kind, name) local n = 0 for _, e in ipairs(effects) do if e[1] == kind and (not name or e[2] == name) then n = n + 1 end end return n end
local fails = 0
local function check(name, ok, detail) print((ok and 'ok   ' or 'FAIL ') .. name .. ((not ok and detail) and ('  -> ' .. tostring(detail)) or '')); if not ok then fails = fails + 1 end end

-- loading and registering
local ok, err = pcall(load_plugin)
check('loads without os/require/io.open', ok, err)
if not ok then realExit(1) end
local reg = effects[1]
check('registers gumshoe', reg and reg[1] == 'register' and reg[2].id == 'gumshoe')
check('help lists the 13 gum commands, gum repeat included', reg and #reg[2].help.commands == 13 and reg[2].help.commands[12].command:find('repeat') ~= nil)
check('repeat setting on the dashboard, off by default', reg and reg[2].settings[3].key == 'repeat' and reg[2].settings[3].default == false)
check('trigger and alias recreated', next(triggers) ~= nil and next(aliases) ~= nil)

-- the alias and colours
input('gum help'); local h = output()
check('gum help prints help, with gum repeat', h:find('Gumshoe, Jaco') ~= nil and h:find('gum repeat') ~= nil, h)
check('no colour names the client lacks', not h:find('<cyan>') and not h:find('<grey>') and h:find('<sky_blue>') ~= nil, h)
input('gum status'); check('gum status works', output():find('gum status') ~= nil)
input('gum bogus'); check('unknown command message', output():find("Unknown command 'bogus'") ~= nil)
input('gumshoe'); check('other words starting with gum go to the game', sent[#sent] == 'gumshoe')

-- dashboard settings, buttons, status
event('ck.plugin.gumshoe.ready', '{"auto":false,"difficulty":"Easy"}')
check('ready applies saved settings', E.gum.auto == false and E.gum.difficulty == 'easy')
event('ck.plugin.gumshoe.setting', 'difficulty', '"Normal"')
check('setting change applies', E.gum.difficulty == 'normal')
input('gum auto on'); local c = last('configure')
check('gum auto on moves the dashboard switch', E.gum.auto == true and c and c[2] == 'auto' and c[3] == true)
event('ck.plugin.gumshoe.action', 'status'); check('Status button runs gum status', output():find('gum status') ~= nil)
advance(1); local st = last('status')
check('status Stopped when idle', st and st[2].state == 'Stopped', st and st[2].state)
local okLines, e2 = pcall(function() for _, l in ipairs{'Front Steps', 'Lost? notebook brief', '', '[Pl: 1 | Ki: 100%]'} do lineIn(l) end end)
check('every line reaches gum.line', okLines, e2)
-- hosts that pass the line to the function instead of setting line/matches
local function hostLine(arg) E.line, E.matches = nil, nil; for _, fn in pairs(triggers) do fn(arg) end end
local seen, gl = {}, E.gum.line
E.gum.line = function(l) seen[#seen + 1] = l; return gl(l) end
local okHost, e3 = pcall(function() hostLine('Front Steps'); hostLine({ 'Kitchen' }); hostLine(nil) end)
E.gum.line = gl
check('line passed as text or match table, or not at all: no error', okHost and seen[1] == 'Front Steps' and seen[2] == 'Kitchen' and #seen == 2, e3 or table.concat(seen, '|'))
check('gum.line(nil) is ignored', pcall(E.gum.line, nil))

-- next-case wait without os
E.gum.caseOver(); input('gum cd'); local cd = output()
check('gum cd shows the wait and a UTC time', cd:find('Next case in 20:00') ~= nil and cd:find('UTC') ~= nil, cd)
advance(1); st = last('status')
check('status Waiting with a deadline', st and st[2].state == 'Waiting' and st[2].deadline == E.gum.nextCase * 1000)
local saved = E.gum.nextCase
load_plugin()
check('wait survives a reload (table.save/io.exists)', E.gum.nextCase == saved)
advance(20 * 60 + 1); local ready = output()
check('reminder when Jaco has a new case', ready:find('Jaco has a new case') ~= nil, ready)

-- plugin control: movement is claimed before walking and handed back after
sent = {}; E.gum.room = 'Entrance Hall'
input('gum go kitchen')
local cl = last('claim')
check('gum go asks for movement first', cl and cl[2][1] == 'movement' and #sent == 0 and not E.gum.running, #sent)
event('ck.plugin.gumshoe.control', 'granted')
check('walks once movement is granted', E.gum.running == true and #sent > 0, #sent)
input('gum stop'); output()
check('gum stop hands movement back', last('release') ~= nil and E.gum.running == false)
local claims = count('claim')
input('gum go kitchen'); event('ck.plugin.gumshoe.control', 'granted')
input('gum go hall')
check('no second claim while it holds movement', count('claim') == claims + 1)
local rel = count('release')
event('ck.plugin.gumshoe.control', 'revoked', 'Boss Summoner'); local rv = output()
check('revoked: stops walking and says who took it', E.gum.running == false and rv:find('Boss Summoner') ~= nil, rv)
input('gum run'); event('ck.plugin.gumshoe.control', 'denied', 'Data Lords Auto'); local dn = output()
check('denied: does not walk and says so', not E.gum.running and dn:find('Data Lords Auto') ~= nil, dn)
input('gum go kitchen'); advance(11); local to = output()
check('no answer in 10 s: gives up with a message', to:find('did not give Gumshoe movement') ~= nil and not E.gum.running, to)
event('ck.plugin.gumshoe.control', 'granted')
check('a late grant after giving up is handed back', not E.gum.running and count('release') > rel)
input('gum go kitchen'); event('ck.plugin.gumshoe.control', 'granted'); E.gum.running = false
rel = count('release'); advance(1); advance(1); local early = count('release'); advance(1)
check('idle 3 s after walking: movement handed back', early == rel and count('release') == rel + 1)
advance(5)
input('gum go nowhere-room'); event('ck.plugin.gumshoe.control', 'granted'); advance(1)
check('status leaves Waiting for movement once the walk ends', last('status')[2].detail ~= 'Waiting for movement control', last('status')[2].detail)

-- repeat (fully auto)
load_plugin(); E.gum.nextCase = nil; output()
local function jacoTrips(text) local n = 0 for _ in text:gmatch('off to Jaco for the next case') do n = n + 1 end return n end
input('gum auto off'); output()
input('gum repeat on'); local on = output()
check('gum repeat on: auto on too, says when', E.gum.auto == true and on:find('Repeat on: next case in 0:05') ~= nil, on)
check('gum repeat on moves both dashboard switches', count('configure', 'repeat') == 1 and last('configure')[2] == 'auto' and last('configure')[3] == true)
advance(1); st = last('status')
check('status: Repeat on, with a deadline', st[2].state == 'Waiting' and st[2].detail:find('Repeat on') ~= nil and st[2].deadline ~= nil, st[2].detail)
advance(4); local trip = output()
check('Jaco ready now: goes for a case after 5 s', jacoTrips(trip) == 1 and last('claim') ~= nil, trip)
event('ck.plugin.gumshoe.control', 'granted'); advance(30); output()
E.gum.running = false
E.gum.caseOver(); advance(20 * 60); local early2 = jacoTrips(output()); advance(5)
check('after a case: the next one 20 min + 5 s later, not before', early2 == 0 and jacoTrips(output()) == 1)
advance(30); E.gum.running = false; output()
advance(30 * 60); local again = output()
check('no case finished in 30 min: tries again', jacoTrips(again) == 1 and again:find('trying again') ~= nil, again)
advance(30); E.gum.running = false
local n0 = count('configure', 'repeat')
input('gum stop'); local stopped = output()
advance(60 * 60)
check('gum stop ends repeat, nothing more starts', not E.gum.running and jacoTrips(output()) == 0 and stopped:find('Repeat off') ~= nil and count('configure', 'repeat') == n0 + 1, stopped)
event('ck.plugin.gumshoe.setting', 'repeat', 'true'); output()
check('dashboard switch turns it on without echoing the setting back', count('configure', 'repeat') == n0 + 1)
input('gum auto off'); local ao = output()
check('gum auto off also ends repeat', ao:find('Repeat off') ~= nil)
-- denied movement while repeating: try again in 2 minutes
input('gum repeat on'); advance(5); output()
event('ck.plugin.gumshoe.control', 'denied', 'Boss Summoner'); local den = output()
advance(119); local tooSoon = jacoTrips(output()); advance(1)
check('movement denied: says so, tries again 2 min later', den:find('tries again in 2 minutes') ~= nil and tooSoon == 0 and jacoTrips(output()) == 1, den)
input('gum repeat off'); output()
-- logging in with repeat saved on: waits 15 s, then goes
load_plugin(); E.gum.nextCase = nil; output()
event('ck.plugin.gumshoe.ready', '{"repeat":true}'); advance(14); local soon = jacoTrips(output()); advance(1)
check('repeat saved on: starts 15 s after login', soon == 0 and jacoTrips(output()) == 1 and count('configure', 'repeat') == 0)
-- right after a case: go and wait at Jaco, or after your own travel commands, or stay put
event('ck.plugin.gumshoe.control', 'granted'); advance(30); E.gum.running = false; output()
sent = {}; E.gum.caseOver(); E.gum.onCulpritDead('Mai'); advance(1); local notYet = #sent
advance(1); event('ck.plugin.gumshoe.control', 'granted'); advance(6); local park = output()
check('culprit dead: off to Jaco to wait (2 s later)', notYet == 0 and sent[1] == 'look' and park:find('Off to Jaco to wait') ~= nil, park)
advance(30); E.gum.running = false; output()
input('gum repeat wait w; n ;up'); local w = output()
check('gum repeat wait <commands>: says and saves it', w:find('then: w; n ;up') ~= nil and files['/package/gumshoe_repeat.lua'].wait == 'w; n ;up', w)
sent = {}; E.gum.caseOver(); advance(59); local before = table.concat(sent, '|'); advance(1)
event('ck.plugin.gumshoe.control', 'granted'); advance(6); lineIn('Briefs Family Garden'); lineIn('Front Steps'); advance(1)
check('no culprit death seen: to Jaco a minute after the case, then the commands from there', before == '' and table.concat(sent, '|') == 'look|use mansion|w|w|w|w|w|w|w|n|up', table.concat(sent, '|'))
advance(30); E.gum.running = false; output()
input('gum repeat wait'); local cur = output()
check('gum repeat wait: shows where', cur:find('at Jaco on the Front Steps, then: w; n ;up') ~= nil, cur)
input('gum repeat wait jaco'); output()
check('gum repeat wait jaco: back to the default', files['/package/gumshoe_repeat.lua'].wait == '' and E.gum.rep.wait == nil)
input('gum repeat off'); output()

-- the same file in Mudlet
local function count_of(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
ok, err = pcall(load_plugin, true)
check('Mudlet: loads with no plugin API', ok, err)
check('Mudlet: no dashboard registration', count('register') == 0)
check('Mudlet: one trigger and one regex alias', count_of(triggers) == 1 and count_of(aliases) == 1 and select(2, next(aliases)).regex ~= nil)
input('gum help'); h = output()
check('Mudlet: gum help with gum repeat, Mudlet colours untouched', h:find('gum repeat') ~= nil and h:find('<cyan>') ~= nil, h)
sent = {}; E.gum.room = 'Entrance Hall'; input('gum go kitchen')
check('Mudlet: walks straight away, no plugin control', #sent > 0 and count('claim') == 0, #sent)
input('gum stop'); output()
E.gum.nextCase = nil; input('gum repeat on'); advance(5); local mt = output()
check('Mudlet: repeat goes for a case', jacoTrips(mt) == 1, mt)
E.gum.running = false; E.gum.caseOver(); advance(20 * 60 + 5)
check('Mudlet: next case 20 min later', jacoTrips(output()) == 1)
-- another package (Autolearn) holds the next case until it's ready, then takes over afterwards
do
  local heard, toJaco = {}, E.gum.toJaco
  E.gum.toJaco = function(_, arrived) if arrived then arrived() end end   -- the walk itself is tested above
  handlers['gumshoe.repeat.starting'] = { function() heard[#heard + 1] = 'starting'; E.gum.hold('Autolearn') end }
  handlers['gumshoe.repeat.done'] = { function() heard[#heard + 1] = 'done'; E.gum.rep.claimed = 'Autolearn' end }
  input('gum repeat off'); E.gum.nextCase = nil; E.gum.running = false
  input('gum repeat on'); heard = {}; advance(6); local held = output()
  check('Mudlet: a hold makes the next case wait', heard[1] == 'starting' and jacoTrips(held) == 0 and held:find('waiting for Autolearn') ~= nil, held)
  E.gum.release('Autolearn'); check('Mudlet: released: off to Jaco', jacoTrips(output()) == 1)
  E.gum.running = false; E.gum.nextCase = nil; E.gum.onCulpritDead(); advance(3); local after = output()
  check('Mudlet: after the case, back at Jaco: done, and the claim replaces the wait commands',
    heard[#heard] == 'done' and after:find('Autolearn carries on until the next case') ~= nil, after)
  E.gum.caseOver(); advance(20 * 60 + 6); output(); advance(181)
  check('Mudlet: a hold never released: goes anyway after 3 minutes', jacoTrips(output()) == 1)
  E.gum.running = false; heard = {}
  input('gum repeat off'); local offd = output()
  check('Mudlet: repeat off tells the others (done)', heard[1] == 'done' and offd:find('Repeat off') ~= nil, table.concat(heard, ','))
  handlers['gumshoe.repeat.starting'], handlers['gumshoe.repeat.done'], E.gum.toJaco = nil, nil, toJaco
  E.gum.nextCase = nil; input('gum repeat on'); advance(5); output()
end
E.gum.running = false
load_plugin(true, true); output()   -- Mudlet runs the script again when it is saved
check('Mudlet: running the script again leaves one trigger and one alias', count_of(triggers) == 1 and count_of(aliases) == 1)
advance(60 * 60)
check('Mudlet: and no leftover repeat timers', jacoTrips(output()) == 0 and not E.gum.rep.on)
E.gum.nextCase = nil; input('gum cd'); check('Mudlet: gum cd', output():find('No finished case') ~= nil)

print(fails == 0 and 'ALL PASSED' or (fails .. ' FAILED')); realExit(fails == 0 and 0 or 1)
