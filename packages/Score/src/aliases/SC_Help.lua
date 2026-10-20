
local helpscreen = [[
score                       - your normal score, with the extras appended
SC show                     - print the extras block on demand
SC features                 - see feature toggles
SC feature <name> <on|off>  - set features on/off
SC constants                - see constant values
SC update                   - Update Score to github latest

Features:
  score.extras - the appended block (damage, tier, heal, training helpers)
  score.regen  - rewrite the Ki/GodKi/BioMass/Heat %% lines into real numbers
]]

print(helpscreen)
