local cmds = {
  {"autobuff on / off",                  "enable or disable auto-rebuffing"},
  {"autobuff cast",                       "manually cast all desired buffs now"},
  {"autobuff",                           "show desired buff list and current state"},
  {"autobuff buffs",                     "browse all known buffs grouped by race"},
  {"autobuff add <skill>",               "add a buff to your desired list"},
  {"autobuff remove <skill>",            "remove a buff from your desired list"},
  {"autobuff newbuff <skill> :: <msg>",   "register a new buff with its expire message"},
  {"autobuff setcast <skill> :: <msg>",    "register a buff's cast (activation) message"},
  {"autobuff setaffects <skill> :: <key>","set MSDP AFFECTS name if it differs from skill"},
  {"autobuff setcmd <skill> :: <command>",  "override cast command (for non-focus skills)"},
  {"autobuff setitem <skill> :: <hold> :: <wear>", "set hold/rewear wrapper (optional, if instrument not worn)"},
  {"autobuff combat <skill>",                   "toggle allow-in-combat for a buff (default: all buffs pause mid-fight)"},
  {"autobuff delbuff <skill>",           "remove a custom buff entirely"},
  {"autobuff settag <skill> <tag>",      "set the race tag for a buff (e.g. Angel, Demon, all)"},
  {"autobuff help",                      "show this help"},
  {"buffwnd",                            "toggle the buff status window"},
  {"buffwnd show / hide",                "open or close the buff status window"},
  {"buffwnd float",                      "toggle docked / floating window"},
}
local sep = "<medium_purple>" .. string.rep("─", 56) .. "<reset>\n"
local out = "\n" .. sep
out = out .. "<slate_grey>  Auto Buff Commands<reset>\n"
out = out .. sep
for _, row in ipairs(cmds) do
  out = out .. string.format("<sky_blue>  %-34s<white>%s<reset>\n", row[1], row[2])
end
out = out .. sep
cecho(out)
