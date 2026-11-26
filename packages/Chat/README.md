# Chat

By **Penguin**. A tabbed chat window (EMCO) that captures OOC, auctions, group tells, dice rolls,
tells, events and says/asks/exclaims/mutters/gives. Type `chatwnd` for the commands.

| Command | What it does |
|---|---|
| `chatwnd show\|hide\|float\|lock\|unlock` | Show, hide, float or lock the window |
| `chatwnd addtab <name> [n]` / `chatwnd remtab <name>` | Add or remove a tab |
| `chatwnd gag <text>` / `ungag` / `gaglist` | Hide lines containing some text |
| `chatwnd notify <tab>` / `unnotify` | Flash when a tab gets a message |
| `chatwnd font\|fontSize\|timestamp\|blink\|blankLine <value>` | Looks and behaviour |
| `chatwnd color <what> <color>`, `border`, `tabtext`, `label`, `title`, `image show\|hide` | Styling |
| `chatwnd save\|load` | Save or load the settings |

Bundles demonnic's EMCO, LoggingConsole and DemonTools (MIT, see `src/resources/LICENSE-MDK.lua`).
