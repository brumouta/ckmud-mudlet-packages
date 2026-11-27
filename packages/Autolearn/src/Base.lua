-- Autolearn's base: the AL namespace and AL.ck, the small helper every other script uses for its
-- tables, settings ("features" are on/off switches, "constants" hold values) and timers.
-- Settings are saved in autolearn.lua in the profile folder. They used to live in Mudlet's
-- "Autolearn" database (Autolearn 3.x and older); those are brought over once.
AL = AL or {}
local ck = AL.ck or {}
AL.ck = ck

local PREFIX, WAS_SET = "AL", "__al_defaults_WAS_SET"
local FILE = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/autolearn.lua"

-- ---------------------------------------------------------------- tables
-- ck:get_table("API.Learning", defaults) is AL.API.Learning, made if missing; defaults are copied
-- in the first time only
function ck:get_table(name, default)
  local head = _G
  name = name and (PREFIX .. "." .. name) or PREFIX
  for w in name:gmatch("[%w_]+") do
    head[w] = head[w] or {}
    head = head[w]
  end
  if default and not head[WAS_SET] then
    ck:copy_table_into(default, head)
    head[WAS_SET] = true
  end
  return head
end

function ck:copy_table_into(t, dst)
  for k, v in pairs(t) do dst[k] = v end
  local mt = getmetatable(t)
  if mt then setmetatable(dst, mt) end
end

function ck:clear_table(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  for _, k in ipairs(keys) do t[k] = nil end
end

function ck:make_enum(name, list)
  local t = {}
  for _, v in ipairs(list) do t[v] = { name .. "." .. v } end
  return t
end

-- ---------------------------------------------------------------- settings
local Features, Constants = {}, {}           -- name -> default (constants wrapped: { value })
local saved = { features = {}, constants = {} }

local function save()
  if type(table.save) == "function" then pcall(table.save, FILE, saved) end
end

function ck:define_feature(name, default) Features[name] = default or false end
function ck:define_constant(name, default) Constants[name] = { default } end

function ck:feature(name)
  if Features[name] == nil then error("unknown feature name: " .. tostring(name)) end
  local v = saved.features[name]
  if v == nil then return Features[name] end
  return v
end

function ck:constant(name)
  if Constants[name] == nil then error("unknown constant name: " .. tostring(name)) end
  local v = saved.constants[name]
  if v == nil then return Constants[name][1] end
  return v
end

function ck:set_feature(name, value)
  saved.features[name] = value and true or false
  save()
  if type(raiseEvent) == "function" then raiseEvent("AL.Feature", name, value) end
end

function ck:set_constant(name, value)
  saved.constants[name] = value
  save()
  if type(raiseEvent) == "function" then raiseEvent("AL.Constant", name, value) end
end

local function names(t)
  local a = {}
  for k in pairs(t) do a[#a + 1] = k end
  table.sort(a)
  return a
end
function ck:feature_names() return names(Features) end
function ck:constant_names() return names(Constants) end

-- Autolearn 3.x and older kept them in Mudlet's database: bring them over the first time this
-- version loads without autolearn.lua (only if that database exists, so none is made).
local function migrate()
  if type(db) ~= "table" or type(db.create) ~= "function" or type(yajl) ~= "table" then return end
  local dbFile = (type(getMudletHomeDir) == "function" and getMudletHomeDir() or ".") .. "/Database_autolearn.db"
  local exists = type(io.exists) == "function" and io.exists(dbFile)
  if not exists then local f = io.open(dbFile); if f then f:close(); exists = true end end
  if not exists then return end
  local ok, schema = pcall(db.create, db, "Autolearn", {
    Toggles = { name = "", value = 0, _unique = { "name" }, _violations = "REPLACE" },
    Constants = { name = "", value = "", _unique = { "name" }, _violations = "REPLACE" },
  })
  if not ok or not schema then return end
  local n = 0
  local okC, rows = pcall(db.fetch, db, schema.Constants)
  for _, r in ipairs(okC and rows or {}) do
    local okV, v = pcall(yajl.to_value, r.value or "")
    if type(r.name) == "string" and okV and type(v) == "table" and v[1] ~= nil then
      saved.constants[r.name] = v[1]; n = n + 1
    end
  end
  local okT, toggles = pcall(db.fetch, db, schema.Toggles)
  for _, r in ipairs(okT and toggles or {}) do
    if type(r.name) == "string" then saved.features[r.name] = r.value == 1; n = n + 1 end
  end
  save()
  if n > 0 then
    cecho("\n<cyan>[ Autolearn ] - <white>Brought over " .. n .. " settings from the old Autolearn database.\n")
  end
end

do
  if type(table.load) == "function" and io.open(FILE) then
    local t = {}
    pcall(table.load, FILE, t)
    if type(t.features) == "table" then saved.features = t.features end
    if type(t.constants) == "table" then saved.constants = t.constants end
  else
    migrate()
  end
end

-- ---------------------------------------------------------------- timers since an event
-- Times:reset("fight") marks now; Times:last("fight") is the seconds since.
local Times = ck:get_table("API.Times", { _marks = {} })
local function now() return type(getEpoch) == "function" and getEpoch() or os.time() end
function Times:create(name) if not self._marks[name] then self._marks[name] = now() end end
function Times:reset(name) self._marks[name] = now() end
function Times:last(name) return now() - (self._marks[name] or now()) end

-- ---------------------------------------------------------------- list output
local console = {}
ck.console = console
function console:header(text, width, color)
  local dashl = math.floor((width - #text - 6) / 2)
  local extra = (dashl * 2 + #text + 6 < width) and 1 or 0
  local left, right = string.rep("-", dashl), string.rep("-", dashl + extra)
  cecho("o" .. left .. "[ <" .. (color or "green") .. ">" .. text .. "<reset> ]" .. right .. "o\n")
  return #left + #right + #text + 6
end
function console:footer(width) echo("o" .. string.rep("-", width - 2) .. "o\n") end
