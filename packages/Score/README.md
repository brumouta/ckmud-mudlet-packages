![shenron](src/resources/shenron.png)

# Score

A standalone Mudlet package for CKMud that makes the `score` command far more
useful: real numbers instead of percentages, your damage at every boost level,
item tier with progress to the next one, and training hints. Fully
self-contained — it does NOT require CK to be installed.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Score.mpackage")`

**Requires the [MSDP](../MSDP) package**, which supplies the stats this package reads. Install it first.

After installation the `SC update` alias keeps it current.

You must turn on `msdp` in settings (the package enforces the correct protocol
settings on connect) — every number below is computed from the MSDP feed.

## What it adds

Type `score` as usual. The percentage lines are rewritten in place:

```
Ki:    5,000                        KI REGEN: 300
GodKi: 400                          GODKI REGEN: 50
```

(`BioMass` for bio-androids and `Heat`/`Dissipation` for androids get the same
treatment.) Then a block is appended, at the `Green Orbs:` line or the closing
line of the sheet, whichever comes first:

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

- **PHY/KI DAM** — your damage per hit at base, (B)oosted, (S)upreme and
  (U)ltimate skill levels, so you can see what a boost is worth.
- **HEAL** — heal factor from INT, WIS and max PL.
- **ITEM TIER** — the loot tier your base PL unlocks, and how much more base PL
  the next tier needs.
- **TRAIN NEXT** — your lowest base stat.
- **GRAVITY** — the gravity that still trains efficiently, against your max.
- **GAUNTLET RUNS** — how many runs your zenni covers.

## Aliases

`SC show` - print the block on demand, without running `score`

`SC` - command list

`SC features` / `SC feature <name> <on|off>` - toggles

`SC update` - update from github latest

## Gravity on the prompt

Your prompt gains a gravity readout, `[5/20x G]` — the room's current gravity
against your maximum, turning green once you are at or above your max. Turn it
off with `SC feature score.prompt_gravity off`.

## Features

- `score.extras` (default on) - the appended block
- `score.regen` (default on) - rewriting the Ki/GodKi/BioMass/Heat lines
- `score.prompt_gravity` (default on) - the gravity readout on the prompt

## Running alongside CK

Score keeps its state under its own `SC` namespace, its own `Score` settings
database, and its own events. Note that CK ships its own score
enhancements (a damage block on the `Green Orbs:` line), so running both will
print two blocks — turn `score.extras` off here, or drop CK's. CK's prompt
also shows gravity, so turn `score.prompt_gravity` off if you run both.

## Development

This is a [muddler](https://github.com/demonnic/muddler) project — run `muddler`
in this directory to produce `build/Score.mpackage`.

```
python3 ../../tools/lint_manifests.py src
cd tests && npm install && node runner.js driver.lua
```
