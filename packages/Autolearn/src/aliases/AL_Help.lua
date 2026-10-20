
local helpscreen = [[
autolearn <target> <speedwalk>  - toggle auto learning (see README for details)
AL features                     - see feature toggles
AL feature <name> <on|off>      - set features on/off
AL constants                    - see constant values
AL constant <name>=<value>      - set a constant value
AL update                       - Update Autolearn to github latest

Panic button: lua AL.API:RESET_ALL()
]]

print(helpscreen)
