# FriezaQuest — Frieza's Spaceship quest helper

Command: `fq`

Automates the Frieza's Spaceship quest from Appule up to the Bridge Access Card (Online).

## Before you start

`fq start` runs `locate` for each item the quest uses up and refuses to start if any is missing:

- an Evermore Fusion Cell (Steering Module)
- a TuffTech x45 battery, a lump of dark matter, a premium circuit board (Power Module)

Starting at a later stage (`fq start power`) only checks what that stage still needs. Nothing is ever taken from clan storage.

## Commands

| Command | Effect |
|---|---|
| `fq help` | List the commands |
| `fq start [stage]` | Check the items, then start (from the Airlock, or a stage) |
| `fq check` | Check the items without starting |
| `fq go` (or `fq run`) | Re-run the current stage's step from where you're standing |
| `fq stage <name>` | Jump to a stage: appule, cuicui, engine, steering, revenge, comms, power, comms2, zarbon, done |
| `fq code <number>` | Set Frieza's door code by hand |
| `fq attack <cmd>` | Attack used on the bosses (default `ss`) |
| `fq status` / `fq stop` | Show the stage / turn the helper off |

## Stages

| Stage | Automated |
|---|---|
| appule | Kill Appule (north or south Airlock), `get caps`, walk to the Entrance and through the hatch |
| cuicui | Kill Cui Cui, read the door code, open Frieza's room, take and wear the armor |
| engine | Open the Engine Hatch (all four hatch passwords), search the five lower rooms for the card, hand it over, wear the uniform |
| steering | `pursue steering`, open the hatch, `repair`, collect the card |
| revenge | `pursue dying`, `say revenge`, `pursue dodoria` and kill him, return |
| comms / power / comms2 | Deliver the note, power the ship via the Electrical Engineer, deliver the crumpled note |
| zarbon | `say surrender` for each card, kill Zarbon, go down to Taiko |

## Done by hand

- Walking to the Engine Hatch. `fq go` there (or one room east of it) runs the hatch.

Cui Cui can't be sensed, so the helper walks there from the Hatch (7 north, then up the Port and Forward rooms, 4 south down the Gangway, west, south). If you're somewhere else, walk to the Hatch and `fq go`.

If you have a trigger that answers "The ... seems to be closed." with `unl`/`open`/move, turn it off while doing the quest: it repeats the last command *you* typed, not the move the helper sent, and walks you the wrong way.
- The Rejuvenation Chamber, if `pursue dying` doesn't track the dying man.

If a step gets stuck, finish it by hand and type `fq go`.
