# YamoshiSpawn — Yamoshi spawn quest helper

Command: `ys`

Runs the three trials in the Temple of the Ancient Saiyajins and the ritual that summons Yamoshi. Start at the altar in **The Echoing Atrium** and type `ys start`.

## Commands

| Command | Effect |
|---|---|
| `ys help` | List the commands |
| `ys start [stage]` | Start from the Atrium (all trials, or from a stage) |
| `ys go` | Restart the current stage; stand in the Atrium first |
| `ys stage <name>` | Set the stage: memory, perception, power, ritual, done |
| `ys attack <cmd>` | Attack used on the bosses (default `ss`) |
| `ys status` / `ys stop` | Show the stage / turn the helper off |
| `yamoportal [no]` | Walk the switch-and-portal rooms, `search;;get fragment` in each (`no` skips the searches) |

## Tetsukai's quiz

When Tetsukai or Tetsusai asks one of the ten known questions about Yamoshi, the answer is said automatically (always on, even with the helper off). Answers are in `YS.QUIZ`.

## Trials

Every stage starts and ends at the Atrium. The vortexes are crossed with `enter vortex`.

| Trial | Automated |
|---|---|
| Memory (west) | `say ready`, record the four flames in the announced order, walk the loop extinguishing each torch, then kill Warlord Kaizor |
| Perception (north) | `say ready`, in each of the six Chambers of Judgment `sense` Fat then Skinny and `touch` the true warrior (Muscular if both are false), then kill Ruthless Varkuun |
| Power (east) | `say ready`, kill the four Evil Shadow warriors in their arenas, then Legendary Renzakai |
| Ritual | `say ritual` at the altar |

## If something goes wrong

Each step waits for a specific game line and stops with a message if it doesn't arrive (90 seconds for bosses). A sense reply it doesn't recognise also stops it after 8 seconds, because a wrong `touch` resets the Trial of Perception. Finish the part by hand, walk back to the Atrium and `ys go`.

The routes assume the temple maze is the same every time (mapped from one full run). If a move hits "Alas, you cannot go that way", the room layout in `src/ys.lua` (`ROUTE`, `BACK`, `PERCEPTION_TOUR`, `POWER_TOUR`) needs updating.
