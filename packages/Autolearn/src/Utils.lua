-- Instead of patching math and table we have a AL.math and AL.table
local ck = AL.ck
local t = ck:get_table("table")
local m = ck:get_table("math")


-- Quality Of Life functions
function m.round(x, n)
    return tonumber(string.format("%." .. n .. "f", x))
end

function m.format(i)
    -- The parentheses matter: gsub returns (string, count), and that stray
    -- count leaks into the caller's argument list when format() is the last
    -- argument of a call.
    return (tostring(i):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", ""))
end

local _unpack
---@diagnostic disable-next-line: deprecated
if table.unpack ~= nil then
    -- At some point table.unpack is included in lua
    ---@diagnostic disable-next-line: deprecated
    _unpack = table.unpack
else
    _unpack = unpack
end

function t.sub(t, i, j)
    return { _unpack(t, i, j) }
end

function t.sample_keys(tb)
    local keys = {}
    for k, v in pairs(tb) do
        table.insert(keys, k)
    end
    return keys[math.random(#keys)]
end

function t.sample_items(tl)
    local pos = math.floor(math.random() * #tl) + 1
    return tl[pos]
end

function t.extend(list, items)
    for _, item in ipairs(items) do
        list[#list + 1] = item
    end
end
