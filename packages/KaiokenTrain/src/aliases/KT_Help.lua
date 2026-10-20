
local helpscreen = [[
kaioken train               - toggle kaioken auto training
KT features                 - see feature toggles
KT feature <name> <on|off>  - set features on/off
KT constants                - see constant values
KT constant <name>=<value>  - set a constant value
KT update                   - Update KaiokenTrain to github latest

Panic button: lua KT.API:RESET_ALL()
]]

print(helpscreen)
