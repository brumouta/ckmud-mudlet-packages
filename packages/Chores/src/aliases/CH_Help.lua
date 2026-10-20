
local helpscreen = [[
chores                      - toggle: off <-> both
chores fish                 - auto fish (castout/reelin, rest when fatigued)
chores quest                - run the royal cook delivery every cooldown
chores both                 - quest first, then fish between cooldowns
chores off                  - stop
CH features                 - see feature toggles
CH feature <name> <on|off>  - set features on/off
CH constants                - see constant values
CH constant <name>=<value>  - set a constant value
CH update                   - Update Chores to github latest

Start fishing modes standing at your fishing spot, holding your pole.
Constants to set: chores.fishing_path (recall/rest/quest-end -> fishing spot),
chores.rest_path (fishing spot -> rest room).
]]

print(helpscreen)
