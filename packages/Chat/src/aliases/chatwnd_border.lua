local chat = Chat
local echo = chat.helpers.echo
local color = matches[2]
chat.config.activeBorder = color
chat.config.windowBorder = color
chat.helpers.retheme()
echo(f"Set border color to {color}")
