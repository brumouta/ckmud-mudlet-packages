# Score

Command: `sc`

Makes CKMud's `score` far more useful: real numbers instead of percentages, your damage at every
boost level, item tier with progress to the next one, and training hints. Originally extracted
from the [CK](https://github.com/CKMud-Mudlet-Scripts/CK) package by fried; it doesn't need CK.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Score.mpackage")`

**Requires the [MSDP](../MSDP) package** (with MSDP turned on in Mudlet's settings): every number
below comes from it, base PL included (it reads that from `score`). Install it first.
`sc update` updates Score.

## What it adds

Type `score` as usual. The percentage lines are rewritten in place:

```
Ki:    5,000                        KI REGEN: 300
GodKi: 400                          GODKI REGEN: 50
```

(`BioMass` for bio-androids and `Heat`/`Dissipation` for androids get the same treatment.) Then a
block is added at the `Green Orbs:` line or the closing line of the sheet, whichever comes first:

```
PHY DAM       : 1,234,567           KI DAM      : 2,345,678
PHY DAM(B)    : ...                 KI DAM(B)   : ...
PHY DAM(S)    : ...                 KI DAM(S)   : ...
PHY DAM(U)    : ...                 KI DAM(U)   : ...
HEAL          : 14,500,000
ITEM TIER     : 6  (need 900,000,000 more base PL for tier 7)
TRAIN NEXT    : SPD (150)
GRAVITY       : 19x to train  (max 20x)
GAUNTLET RUNS : 5
```

- **PHY/KI DAM:** your damage per hit at base, (B)oosted, (S)upreme and (U)ltimate skill levels.
- **HEAL:** heal factor from INT, WIS and max PL.
- **ITEM TIER:** the loot tier your base PL unlocks, and how much more the next tier needs.
- **TRAIN NEXT:** your lowest base stat.
- **GRAVITY:** the gravity that still trains efficiently, against your max.
- **GAUNTLET RUNS:** how many runs your zenni covers.

The prompt also gains `[5/20x G]`: the room's gravity against your max, green once you're at it.

## Commands

| Command | What it does |
|---|---|
| `sc` / `sc help` | The commands and which parts are on |
| `sc show` | The block, without running `score` |
| `sc extras on\|off` | The block on the score sheet (saved) |
| `sc regen on\|off` | The Ki/GodKi/BioMass/Heat lines in real numbers (saved) |
| `sc gravity on\|off` | Gravity on the prompt (saved) |
| `sc update` | Update Score to the latest release |

`SC` works as well as `sc`. The switches are saved in `score.lua` in your profile folder.

## Changes in 3.0

Score is now one Lua file like the newer packages. `SC features` and
`SC feature score.<name> on|off` are now `sc extras|regen|gravity on|off`, and your 2.x switches
are brought over the first time 3.0 loads. Name, race and base PL now come from the MSDP package.
It no longer changes Mudlet's protocol settings or reconnects by itself.

## Development

`python3 tools/build.py Score` builds `dist/Score.mpackage`, and `lua tests/Score_test.lua`
(from the repo root) tests it.
