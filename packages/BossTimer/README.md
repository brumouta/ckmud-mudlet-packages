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
| `boss help` | List the commands |

`boss window`, `boss warn` and `boss flash` are saved (in `BossTimer.lua` in your profile folder) and come back when Mudlet restarts; the window reopens where you left it.

Doesn't need any other package.
