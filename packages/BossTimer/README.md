# BossTimer — boss respawn timer

Command: `boss`

Counts down to CKMud's boss respawn so you can be there first. The time comes from `uptime`:

```
 Boss Respawn:    16 min 35 sec remaining
```

## How it works

- **Whenever `uptime` is shown**, by you or by the package, it reads the Boss Respawn line and starts a countdown to that exact moment. Server time zones don't matter.
- **It warns you** 5 minutes and 1 minute before (`boss warn` changes this), says when the bosses have respawned, and flashes Mudlet's taskbar icon.
- **It keeps itself in sync.** It quietly asks `uptime` 10 seconds after you log in and 1 minute after each respawn, to learn when the next one is. Those automatic checks are hidden from your screen; an `uptime` you type yourself is shown as normal.

## Commands

| Command | Effect |
|---|---|
| `boss` | Time left until the respawn |
| `boss check` | Ask `uptime` now (shown on screen) |
| `boss window on\|off` | A small movable window with a live countdown |
| `boss warn <min,...>` | Minutes before the respawn to warn at, e.g. `boss warn 10,5,1` (default 5,1) |
| `boss flash on\|off` | Flash Mudlet's taskbar icon at the respawn |
| `boss help` | List the commands |

Doesn't need any other package.
