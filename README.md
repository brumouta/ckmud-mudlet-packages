# CKMud Mudlet Packages

Self-contained [Mudlet](https://www.mudlet.org/) packages for CKMud: bots, event and quest automation, and a better score sheet. None of them need the CK package installed.

| Package | Command | What it does |
|---|---|---|
| [Autolearn](packages/Autolearn) | `autolearn`, `AL` | Masters all your skills and learns new ones once their prerequisites are mastered. |
| [Chores](packages/Chores) | `chores fish\|quest\|both\|off`, `CH` | Automates fishing, the royal cook delivery quest and the gravedigger excavation. |
| [KaiokenTrain](packages/KaiokenTrain) | `kaioken train`, `KT` | Trains kaioken to max mastery: raises it step by step, drinks, rests and stops when mastered. |
| [Score](packages/Score) | `score`, `SC` | A richer `score`: real numbers, damage at every boost level, item tier progress, training hints. |
| [DataLords](packages/DataLords) | `dl2 help` | Runs the **Data Lords v2.0** event boss chain when *you* requested it, pausing for rivals (yours or your group's). |
| [Blackjack](packages/Blackjack) | `bj help` | Plays **blackjack** with basic strategy after you `cjoin`, and tracks wins, zenni, Lucky Tails and XP. |
| [FriezaQuest](packages/FriezaQuest) | `fq help` | Automates the **Frieza's Spaceship** quest from Appule to the Bridge Access Card. |
| [YamoshiSpawn](packages/YamoshiSpawn) | `ys help` | Runs the three Temple trials and the ritual that **summons Yamoshi**. |

Install only the ones you want.

## Installing

Paste this into Mudlet's input line, replacing `<Package>` with a name from the table (it is case-sensitive, e.g. `Score` or `FriezaQuest`):

```
lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/<Package>.mpackage")
```

Or download the `.mpackage` from the [latest release](../../releases/latest) and use **Toolbox → Package Manager → Install**. To upgrade, uninstall the old version first (Autolearn, Chores, KaiokenTrain and Score also have an `<prefix> update` alias, e.g. `SC update`).

## Repository layout

There are two kinds of package, built differently:

```
packages/
  Autolearn/ Chores/ KaiokenTrain/ Score/     muddler projects
    mfile                 name, version, author
    src/                  triggers/aliases/scripts as muddler JSON + .lua files
    tests/                Node + fengari simulation of a Mudlet session (driver.lua)
  Blackjack/ DataLords/ FriezaQuest/ YamoshiSpawn/   single-script packages
    package.json          version, triggers (patterns + one-line scripts), aliases
    src/<Package>.lua     all the logic, in one Lua table named after its command (bj, dl2, fq, ys)
tests/                    Lua tests for the single-script packages + run.sh for everything
tools/
  build.py                builds the single-script packages into dist/
  lint_manifests.py       checks every muddler trigger/alias actually has a script
  muddle.sh               builds the muddler packages locally
```

## Building

**Single-script packages** (Python 3 only):

```bash
python3 tools/build.py          # all of them -> dist/
python3 tools/build.py FriezaQuest    # just one
```

**Muddler packages** (needs Java). This downloads [muddler](https://github.com/demonnic/muddler) into `~/.cache/muddler` the first time, the same release CI uses:

```bash
sh tools/muddle.sh              # all four -> packages/<Package>/build/<Package>.mpackage
sh tools/muddle.sh Score        # just one
```

## Testing

```bash
sh tests/run.sh
```

Needs Lua 5.1+, Python 3 and Node (Node is only used for the muddler packages; their tests are skipped without it). What it covers:

- **Blackjack, DataLords, FriezaQuest, YamoshiSpawn:** Mudlet's API is stubbed and real game output is replayed. YamoshiSpawn walks a model of the temple map, so a wrong turn fails the test.
- **Autolearn, Chores, KaiokenTrain, Score:** each manifest is linted, because muddler silently ships an empty script if a trigger's `.lua` file is missing. Then the real package sources run through a simulated session (connect → MSDP → prompts → the bot).

## Releasing

Bump the version (`package.json` or `mfile`), commit, then tag:

```bash
git tag v2026.10.21 && git push --tags
```

The release workflow runs every test, builds all eight packages and attaches them to a GitHub release. That's what the install links and the `update` aliases download.

## Credits and license

Autolearn, Chores, KaiokenTrain and Score were extracted from the [CK package](https://github.com/CKMud-Mudlet-Scripts/CK) by Jason Fried ("fried") and extended. Their install and update links now point at this repository. Everything is released under the [Apache 2.0 license](LICENSE), the same as CK.
