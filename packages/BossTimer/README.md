# BossTimer — boss respawn timer

Command: `boss`

Counts down to CKMud's boss respawn so you can be there first. The time comes from `uptime`:

```
 Boss Respawn:    16 min 35 sec remaining
```

## How it works

- **Whenever `uptime` is shown**, by you or by the package, it reads the Boss Respawn line and starts a countdown to that exact moment. Server time zones don't matter.
- **After a respawn or a copyover it assumes the next respawn is 20 minutes away** and starts counting down straight away, warnings included, then checks `uptime` and switches to the exact time. Until then the time shows with a `~` (e.g. `~19m 30s`).
- **It warns you** 5 minutes and 1 minute before (`boss warn` changes this), says when the bosses have respawned, and flashes Mudlet's taskbar icon.
- **It keeps itself in sync.** It quietly asks `uptime` 10 seconds after you log in, 1 minute after each respawn, and 5 seconds after a **copyover** (`Copyover recovery complete.`), which restarts the server and its uptime, to learn when the next one is. Whenever it doesn't know the respawn time (just installed, or a check went unanswered) it also asks 5 seconds after loading and then every 5 minutes until it knows, but not while you're disconnected. Those automatic checks are hidden from your screen; an `uptime` you type yourself is always shown.

## Commands

| Command | Effect |
|---|---|
| `boss` | Time left until the respawn |
| `boss check` | Ask `uptime` now (shown on screen) |
| `boss window on\|off` | A small movable window with a live countdown |
| `boss warn <times>` | When to warn before the respawn: minutes (`boss warn 10,5,1`), decimals (`boss warn 1,0.5`) or seconds (`boss warn 2,30s`). Default 5,1 |
| `boss flash on\|off` | Flash Mudlet's taskbar icon at the respawn |
| `boss find` | Walk to the nearest boss (👹) on the world map, for bosses `pursue` can't reach. See below |
| `boss find stop` | Stop walking |
| `boss help` | List the commands |

`boss window`, `boss warn` and `boss flash` are saved (in `BossTimer.lua` in your profile folder) and come back when Mudlet restarts; the window reopens where you left it.

## Finding a boss on the map

`boss find` sends `look`, finds you (🧍) and the nearest 👹 on the room map, and walks there one room at a time, reading the map again after every move (bosses wander). When the boss is 10 or more rooms away along the way it's going, it uses `dash <direction>` (10 rooms at once) and looks again once the dash is over (*You fly quickly through the area!*). When the 👹 disappears under your 🧍 you're there: *You're on the boss*.

**No 👹 in sight: it searches the map.** It dashes north until the dash can't go on (*Alas, you cannot go that way...* / *Your dash is halted by an obstacle.* / *You can't dash in that direction.*), then west the same way, into the north-west corner. From there it sweeps: east to the other side, one dash (10 rooms) south, back west, south again, and so on. The map shows 5 rows above and below you, so 10-room strips leave no gaps. As soon as a 👹 shows up on any map (also the ones drawn during a dash) it lets the dash finish, looks, and walks to it. If the south dash hits the bottom edge, the whole map has been swept and it says so.

It also stops after 40 moves towards a boss or 150 search dashes, when a step is blocked, or when a move brings nothing back for 15 seconds. `boss find stop` stops it any time. The dash command can be changed with `lua BossTimer.dashCmd = "dash %s"`.

Doesn't need any other package.
