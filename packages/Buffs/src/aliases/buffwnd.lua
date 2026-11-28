local action = matches[2]
if action == "show" then
    BuffWindow:show()
elseif action == "hide" then
    BuffWindow:hide()
elseif action == "font" then
    BuffWindow:setFont(matches[3])
elseif action == "float" then
    BuffWindow:float()
else
    BuffWindow:toggle()
end
