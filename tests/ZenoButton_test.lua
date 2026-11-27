-- zb: the Zeno Button shortcuts. Run from the repo root: lua tests/ZenoButton_test.lua
local sent, timers, modules, removed = {}, {}, { "Other", "Zeno Button" }, {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
function tempTimer(_, f) timers[#timers + 1] = f end
function getModules() return modules end
function uninstallModule(n) removed[#removed + 1] = n end
local function ok(c, what) assert(c, what); print("OK  " .. what) end
dofile("packages/ZenoButton/src/ZenoButton.lua")

local want = {
  e = "recall,press button,s,s,enter vortex",
  v = "recall,press button,s,e,e,enter vortex",
  n = "recall,press button,s,w,w,enter vortex",
  k = "recall,press button,n,e,e,enter vortex",
  i = "recall,press button,n,w,w,enter vortex",
}
for k, route in pairs(want) do
  sent = {}; zb.go(k)
  ok(table.concat(sent, ",") == route, "pb" .. k .. " sends the same as the old module")
end
sent = {}; zb.command("earth")
ok(table.concat(sent, ",") == want.e, "zb earth goes to Earth")
sent = {}; LOG = ""; zb.command("x")
ok(#sent == 0 and LOG:find("Unknown"), "an unknown command sends nothing")
LOG = ""; zb.command(nil)
ok(LOG:find("pbk") and LOG:find("Konats"), "zb help lists the aliases")

ok(#timers == 1, "the module check waits until the package has loaded")
timers[1]()
ok(#removed == 1 and removed[1] == "Zeno Button", "the old Zeno Button module is removed, nothing else")
modules = { "Other" }; removed = {}; zb.dropOldModule()
ok(#removed == 0, "nothing is removed when the module isn't there")
