# MSDP — shared MSDP data for CKMud packages

Command: `msdp`

The one package that talks MSDP to CKMud. Install it **before** Autolearn, Chores, KaiokenTrain, Score or DataLords2. They read their stats from it, and print a red "needs the MSDP package" message if it's missing.

## What it does

- **Subscribes to everything.** On connect it asks the server which variables it can report (`LIST REPORTABLE_VARIABLES`) and subscribes to all of them, plus the 46 it knows. New variables the MUD adds are picked up automatically.
- **Converts and shares.** Values are converted to numbers and kept in `MSDP.Player`, `MSDP.Room` and `MSDP.Target`, using the field names the CK packages always used (`Pl`, `MaxPl`, `Ki`, `Stats.STR`, `Room.Gravity`, `Target.Health`…). Variables it doesn't know are kept as sent in `MSDP.raw`.
- **Fills in what MSDP no longer sends.** Your **name**, **race** and **base PL** come from your `score` sheet. If the server ever sends `CHARACTER_NAME`, `RACE` or `BASE_PL` again, those win.
- **Survives reloads.** MSDP only reports a variable when it changes, so after a reload it replays what Mudlet already has.

## Commands

| Command | Effect |
|---|---|
| `msdp` | List the commands |
| `msdp status` | When the last update arrived, how many variables the server sends, your name / race / base PL |
| `msdp show` | Every current value |
| `msdp report` | Subscribe to everything again |
| `msdp debug on\|off` | Say when updates start arriving |

Type `score` once after logging in so the name, race and base PL are filled in.

## For package authors

```lua
MSDP.Player.MaxPl, MSDP.Player.Stats.STR, MSDP.Room.Gravity, MSDP.Target.name, MSDP.cmd_stack
MSDP:last_update()     -- seconds since the server's last update tick
MSDP:report()          -- subscribe again
```

Events: `MSDP.changed (kind, field, value)` for every change, where kind is `Player`, `Stats`, `BaseStats`, `Room`, `Target`, `MSDP` or `raw`; `MSDP.tick` for each server update; `MSDP.loaded` when the package (re)loads.

The Muddler packages copy these values into their own tables through a small bridge (`scripts/.../MSDP.lua` in each), so the rest of their code didn't change.
