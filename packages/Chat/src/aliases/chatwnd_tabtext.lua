local chat = Chat
local echo = chat.helpers.echo
local color = matches[2]
chat.config.activeText = color
chat.config.inactiveText = color
chat.helpers.retheme()
echo(f"Set tab text color to {color}")
