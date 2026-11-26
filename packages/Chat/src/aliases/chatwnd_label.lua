local chat = Chat
local echo = chat.helpers.echo
local color = matches[2]
chat.config.title = color
chat.helpers.retheme()
echo(f"Set chat label color to {color}")
