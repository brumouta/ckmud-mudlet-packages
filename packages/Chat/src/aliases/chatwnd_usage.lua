local chat = Chat
local echo = chat.helpers.echo
local aliases = {
  ["chatwnd save"] = "saves your config to disk",
  ["chatwnd update"] = "update Chat to the latest release",
  ["chatwnd load"] = "loads your config from disk",
  ["chatwnd addtab <tabname>"] = "adds a tab to your chat",
  ["chatwnd remtab <tabname>"] = "removes a tab from your chat",
  ["chatwnd fontSize"] = "set the font size for the consoles",
  ["chatwnd font"] = "set the font to use for the consoles",
  ["chatwnd blink <true|false>"] = "turn blinking on/off",
  ["chatwnd blankLine <true|false>"] = "turn inserting a blank line between messages on/off",
  ["chatwnd timestamp <true|false>"] = "turn timestamps on/off",
  ["chatwnd show"] = "show the chat",
  ["chatwnd hide"] = "hide the chat",
  ["chatwnd gaglist"] = "prints out the list of gag patterns",
  ["chatwnd gag <pattern>"] = "add a gag pattern",
  ["chatwnd ungag <pattern>"] = "remove a gag pattern",
  ["chatwnd notify <tabName>"] = "turn on OS notifications for tabName",
  ["chatwnd unnotify <tabName>"] = "turn off OS notifications for tabName",
  ["chatwnd float"] = "toggle the chat window between docked (inside Mudlet) and free-floating (separate draggable window)",
  ["chatwnd image show|hide"] = "show or hide the decorative image in the bottom-right corner of the chat window",
  ["chatwnd border <color>"] = "set both the active tab border and window border to the same color at once (e.g. 'chatwnd border goldenrod')",
  ["chatwnd tabtext <color>"] = "set the text color for all tabs (active and inactive) at once",
  ["chatwnd label <color>"] = "set the color of the chat window label/title text",
  ["chatwnd color <option> <value>"] = "used to change individual colors for the active/inactive tab, and the background color for the consoles. 'chatwnd color' with no options will print out available options",
}

echo("\nAvailable aliases for the Standalone Chat package")
echo()
for name, desc in spairs(aliases) do
  echo(f"* {name}")
  echo(f"  * {desc}")
end
