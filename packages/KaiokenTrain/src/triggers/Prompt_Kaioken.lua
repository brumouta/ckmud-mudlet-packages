local matches = multimatches[2]
local Player = KT.Player
Player.Kaioken = tonumber(matches.CURR)
Player.MKaioken = tonumber(matches.MAX)
KT.PromptFlags.Kaioken = true