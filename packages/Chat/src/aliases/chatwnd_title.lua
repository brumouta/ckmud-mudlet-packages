local title = matches[2]
if title == "clear" then
  title = ""
end
Chat.container:setTitle(title)
