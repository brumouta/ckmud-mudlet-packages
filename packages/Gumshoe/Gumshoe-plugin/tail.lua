-- Gumshoe for Mudlet and the CKMud client, part 3 of 3: what the Mudlet package did with an XML
-- trigger and alias, repeat (fully auto), and in the CKMud client the Plugins dashboard card and
-- plugin control. Everything here works in both, except where it checks CLIENT.
local G = gum
local CLIENT = G.client
local ID = 'gumshoe'   -- the same id as in mud.plugin.register below
local P

-- Mudlet runs scripts again when they are saved: drop what the last run created first.
for _, t in ipairs(G.temp or {}) do
  if t[1] == 'trigger' then killTrigger(t[2]) elseif t[1] == 'alias' then killAlias(t[2]) else killTimer(t[2]) end
end
if G.rep then for _, k in ipairs{ 'timer', 'watchdog', 'park' } do if G.rep[k] then killTimer(G.rep[k]) end end end
G.temp = {}
local function keep(kind, id) G.temp[#G.temp + 1] = { kind, id }; return id end

-- The XML trigger "gum Every line" (^.*$): every line goes to gum.line.
keep('trigger', tempRegexTrigger('^.*$', function() gum.line(line) end))

-- The XML alias ^gum(?:\s+(\w+)(?:\s+(.+))?)?$ : gum [command [argument]]
if CLIENT then
  mud.alias('gum', function(rest)
    local c, arg = rest:match('^([%w_]+)%s*(.-)%s*$')
    if rest ~= '' and not c then c = rest end
    G.command(c, arg ~= '' and arg or nil)
  end)
else
  keep('alias', tempAlias([[^gum(?:\s+(\w+)(?:\s+(.+))?)?$]], function()
    local function arg(s) if s and s ~= '' then return s end end
    G.command(arg(matches[2]), arg(matches[3]))
  end))
end

G.rep = { on = false }   -- repeat (fully auto), see below
local rep = G.rep
local setRepeat, setWait -- defined with the repeat section

-- `gum auto on|off` also moves the dashboard switch; `gum repeat [on|off]` is added here.
local command = G.command
G.command = function(c, arg)
  if c == 'repeat' then
    local where = arg and arg:match('^wait%s*(.-)$')
    if where then return setWait(where) end
    if arg == 'on' then setRepeat(true, 'command') elseif arg == 'off' then setRepeat(false, 'command')
    elseif arg == nil then setRepeat(not rep.on, 'command')
    else G.info('yellow', 'gum repeat on or off') end
    return
  end
  command(c, arg)
  if c == 'auto' then
    if P then P.configure('auto', G.auto == true) end
    if not G.auto and rep.on then setRepeat(false, 'command') end
  end
end
table.insert(G.HELP, { 'gum repeat [on|off]', 'Fully auto: after each case, open the next one by itself when Jaco has it (20 minutes)' })
table.insert(G.HELP, { 'gum repeat wait [jaco|here|<commands>]', 'Where repeat waits between cases: at Jaco (default), where you are, or after your own travel commands (; between them)' })

-- Plugin control (CKMud client): Gumshoe asks for movement before it walks, so another plugin
-- can't steer the character at the same time, and hands it back once it stops. Every walk starts
-- in G.run, G.go or G.toJaco (also when gum auto starts the run by itself), so those wait for the
-- grant. Mudlet has no plugin control, so there Gumshoe walks straight away.
local control = { owned = false, pending = nil, timer = nil, idle = 0 }
local shown   -- the last status sent to the dashboard (see the tick at the end)
local function release()
  if control.timer then killTimer(control.timer); control.timer = nil end
  control.pending = nil; control.idle = 0
  if control.owned and P then P.release() end
  control.owned = false
end
local stop = G.stop
if CLIENT then
  local function needsMovement(name)
    local walk = G[name]
    G[name] = function(...)
      if control.owned then control.idle = 0; return walk(...) end
      local args = { ... }
      control.pending = function() return walk(unpack(args)) end
      if control.timer then killTimer(control.timer) end
      control.timer = tempTimer(10, function()
        control.timer = nil
        if control.pending then control.pending = nil; G.info('yellow', 'Plugin control did not give Gumshoe movement. Try again when other plugins stop.') end
      end)
      if P then P.status{ state = 'Waiting', detail = 'Waiting for movement control' }; shown = nil end
      P.claim{ 'movement' }
    end
  end
  needsMovement('run'); needsMovement('go'); needsMovement('toJaco')
  G.stop = function(...) local r = stop(...); release(); return r end

  registerAnonymousEventHandler('ck.plugin.' .. ID .. '.control', function(_, result, owner)
    if result == 'granted' then
      if control.timer then killTimer(control.timer); control.timer = nil end
      local go = control.pending
      control.pending = nil
      if go then control.owned = true; control.idle = 0; go()
      elseif not control.owned and P then P.release() end
    elseif result == 'denied' or result == 'revoked' then
      local was = control.owned or control.pending
      control.owned = false; control.pending = nil
      if control.timer then killTimer(control.timer); control.timer = nil end
      if G.running then stop() end
      if was then
        if rep.on then
          G.info('yellow', 'Movement is with ' .. tostring(owner or 'another activity') .. ': repeat tries again in 2 minutes.')
          rep.retry(120)
        else
          G.info('yellow', 'Movement went to ' .. tostring(owner or 'another activity') .. ': Gumshoe stopped. Run it again when ready.')
        end
      end
    end
  end)
end

-- Repeat (fully auto): after each case, open the next one by itself as soon as Jaco has it.
-- Jaco has a new case 20 minutes after the last one is finished; Gumshoe already tracks that in
-- G.nextCase (G.caseOver). Repeat turns Auto on, so every case is also run and accused by itself.
-- If no case finishes within 30 minutes of opening one (no case from Jaco, a walk that stopped),
-- it tries again. gum stop or gum repeat off ends it. In the client the dashboard setting keeps it
-- on across logins; in Mudlet it lasts until Mudlet closes.
local WATCHDOG = 30 * 60
local function cancel(name) if rep[name] then killTimer(rep[name]); rep[name] = nil end end
local startCase
local function schedule(delay)
  cancel('timer')
  rep.at = getEpoch() + delay
  rep.timer = tempTimer(delay, startCase)
end
startCase = function()
  rep.timer, rep.at = nil, nil
  if not rep.on then return end
  if G.running or control.pending then return schedule(60) end   -- busy: look again in a minute
  cancel('watchdog')
  local function watch()
    rep.watchdog = nil
    if not rep.on then return end
    if G.running then rep.watchdog = tempTimer(300, watch); return end   -- still on it: check again later
    G.info('yellow', 'Repeat: no case finished in 30 minutes, trying again'); startCase()
  end
  rep.watchdog = tempTimer(WATCHDOG, watch)
  G.info('green', 'Repeat: off to Jaco for the next case (gum repeat off to stop)')
  G.toJaco()
end
local function untilJaco(extra) return math.max(0, (G.cooldownLeft and G.cooldownLeft()) or 0) + extra end
rep.retry = function(delay) if rep.on then schedule(delay) end end

setRepeat = function(on, from)
  if on == rep.on then
    if from == 'command' then
      local left = rep.at and math.floor(math.max(0, rep.at - getEpoch()))
      G.info('white', 'Repeat is already ' .. (on and 'on' or 'off') .. (on and left
        and (': next case in ' .. ('%d:%02d'):format(math.floor(left / 60), left % 60)) or ''))
    end
    return
  end
  rep.on = on
  if from == 'command' and P then P.configure('repeat', on) end
  if on then
    if not G.auto then G.auto = true; if P then P.configure('auto', true) end end
    -- at login, give the session a moment before walking anywhere
    if not G.running then schedule(untilJaco(from == 'saved' and 15 or 5)) end
    local left = math.floor(math.max(0, (rep.at or getEpoch()) - getEpoch()))
    G.info('green', 'Repeat on: ' .. (G.running and 'the next case opens by itself when this one is done'
      or ('next case in ' .. ('%d:%02d'):format(math.floor(left / 60), left % 60))) .. '. gum repeat off to stop.')
  else
    cancel('timer'); cancel('watchdog'); cancel('park'); rep.at = nil
    G.info('white', 'Repeat off')
  end
end

-- Where to wait between cases: nil goes to Jaco on the Front Steps, 'here' stays put, anything
-- else is sent as travel commands (; between them, your aliases work too). Kept in a file.
local function waitFile() return getMudletHomeDir and (getMudletHomeDir() .. '/gumshoe_repeat.lua') end
do
  local f, saved = waitFile(), {}
  if f and table.load and ((io.exists and io.exists(f)) or (io.open and io.open(f))) then pcall(table.load, f, saved) end
  if type(saved.wait) == 'string' and saved.wait ~= '' then rep.wait = saved.wait end
end
local function describeWait()
  if not rep.wait then return 'at Jaco on the Front Steps' end
  if rep.wait == 'here' then return 'where the case ends' end
  return 'after: ' .. rep.wait
end
setWait = function(where)
  if where ~= '' then
    if where == 'jaco' or where == 'default' then rep.wait = nil else rep.wait = where end
    local f = waitFile()
    if f and table.save then pcall(table.save, f, { wait = rep.wait or '' }) end
  end
  G.info('green', 'Repeat waits for the next case ' .. describeWait())
end

-- Right after a case is over: head to where repeat waits (a few seconds, for the fight to end)
local function park()
  cancel('park')
  rep.park = tempTimer(3, function()
    rep.park = nil
    if not rep.on or G.running then return end
    if rep.wait == 'here' then return end
    if rep.wait then
      G.info('green', 'Repeat: off to wait for the next case (' .. rep.wait .. ')')
      for part in rep.wait:gmatch('[^;]+') do
        part = part:match('^%s*(.-)%s*$')
        if part ~= '' then
          if type(expandAlias) == 'function' then expandAlias(part, false) else send(part, false) end
        end
      end
      return
    end
    G.toJaco(nil, function() G.info('green', 'Repeat: waiting with Jaco for the next case') end)
  end)
end

local caseOver = G.caseOver
G.caseOver = function(...)
  local r = caseOver(...)
  if rep.on then cancel('watchdog'); schedule(untilJaco(5)); park() end
  return r
end
local stopWalking = G.stop
G.stop = function(...)
  local r = stopWalking(...)
  if rep.on then setRepeat(false, 'command') end
  return r
end

if not CLIENT then return end
-- ---------------------------------------------------------------- CKMud client only from here

local function configure(values, from)
  if type(values) ~= 'table' then return end
  if values.auto ~= nil then
    G.auto = values.auto == true
    if not G.auto and rep.on then setRepeat(false, 'command') end
  end
  if type(values.difficulty) == 'string' then G.difficulty = values.difficulty:lower() end
  if values['repeat'] ~= nil then setRepeat(values['repeat'] == true, from) end
end
local function decode(value)
  local ok, v = pcall(yajl.to_value, value)
  if ok then return v end
end

registerAnonymousEventHandler('ck.plugin.' .. ID .. '.ready', function(_, encoded) configure(decode(encoded), 'saved') end)
registerAnonymousEventHandler('ck.plugin.' .. ID .. '.setting', function(_, key, encoded)
  local value = decode(encoded)
  if value ~= nil then configure({ [key] = value }, 'setting') end
end)
registerAnonymousEventHandler('ck.plugin.' .. ID .. '.action', function(_, key) G.command(key) end)

local help = {}
for _, h in ipairs(G.HELP) do help[#help + 1] = { command = h[1], description = h[2] } end

P = mud.plugin.register{
  -- Written out (not variables) so the catalog tools can read them. Raise the version on every
  -- change, so the client offers the update (1.12.0: repeat waits at Jaco or a place of your choice, built on Gumshoe.mpackage 1.10.2).
  api = 1, id = 'gumshoe', name = 'Gumshoe', version = '1.12.0',
  description = "Jaco's party mysteries at the Briefs house (help mansion): walks the house, searches every room, questions every guest, opens the sealed rooms, confronts the secrets and works out who did it.",
  settings = {
    { key = 'auto', label = 'After Open case: run it and accuse when sure', type = 'boolean', default = true },
    { key = 'difficulty', label = 'Case difficulty', type = 'choice', options = { 'Easy', 'Normal', 'Hard' }, default = 'Hard' },
    { key = 'repeat', label = 'Repeat: open the next case by itself every 20 minutes (fully auto)', type = 'boolean', default = false },
  },
  actions = {
    { key = 'case', label = 'Open case' }, { key = 'run', label = 'Run' }, { key = 'stop', label = 'Stop' },
    { key = 'solve', label = 'Solve' }, { key = 'status', label = 'Status' }, { key = 'cd', label = 'Next case' },
  },
  help = { summary = 'gum case opens a case with Jaco (needs the return capsule, or instant transmission to Bulma). '
    .. 'gum run does the legwork and solves it. Everything is also on the buttons.', commands = help },
}

-- Dashboard status: what the case is doing, or how long until Jaco has the next one.
mud.tick(1, function()
  -- Hand movement back after 3 idle seconds (gum auto starts its run about 1 s after the case).
  if control.owned and not G.running and not control.pending then
    control.idle = control.idle + 1
    if control.idle >= 3 then release() end
  end
  if control.pending then return end
  local s
  if G.running then
    local c = G.case or {}
    s = { state = 'Running', detail = (c.title or 'Case') .. ' · evidence ' .. (G.evFound or 0) .. ' of '
      .. (G.evTotal or '?') .. (G.room and (' · ' .. G.room) or '') }
  else
    local left = G.cooldownLeft and G.cooldownLeft()
    if rep.on and rep.at then
      s = { state = 'Waiting', detail = 'Repeat on: next case opens by itself', deadline = math.floor(rep.at * 1000) }
    elseif left and left > 0 then
      s = { state = 'Waiting', detail = 'Next case from Jaco', deadline = G.nextCase * 1000 }
    else
      s = { state = 'Stopped', detail = 'Ready: Open case, or gum case' }
    end
  end
  local key = s.state .. '|' .. s.detail .. '|' .. tostring(s.deadline)
  if key ~= shown then shown = key; P.status(s) end
end)
