local chat = Chat
local echo = chat.helpers.echo
local action = matches[2]
if action == "show" then
    chat.config.showImage = true
    chat.helpers.setupImage()
    echo("Chat image shown.")
elseif action == "hide" then
    chat.config.showImage = false
    chat.helpers.setupImage()
    echo("Chat image hidden.")
end
