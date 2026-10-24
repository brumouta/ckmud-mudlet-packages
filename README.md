# CKMud Mudlet Packages

Self-contained [Mudlet](https://www.mudlet.org/) packages for CKMud: bots, event and quest automation, and a better score sheet. None of them need the CK package installed.

| Package | Command | What it does |
|---|---|---|
| [MSDP](packages/MSDP) | `msdp` | **Install this first.** Subscribes to every MSDP variable CKMud offers and shares the values (plus your name, race and base PL from `score`) with the packages below. |
| [Autolearn](packages/Autolearn) | `autolearn`, `AL` | Masters all your skills and learns new ones once their prerequisites are mastered. |
| [Chores](packages/Chores) | `chores fish\|quest\|both\|off`, `CH` | Automates fishing, the royal cook delivery quest and the gravedigger excavation. |
| [KaiokenTrain](packages/KaiokenTrain) | `kaioken train`, `KT` | Trains kaioken to max mastery: raises it step by step, drinks, rests and stops when mastered. |
| [Score](packages/Score) | `score`, `SC` | A richer `score`: real numbers, damage at every boost level, item tier progress, training hints. |
| [DataLords2](packages/DataLords2) | `dl2 help` | Runs the **Data Lords v2.0** event boss chain (not Data Lords 1 or 3) when *you* requested it, pausing for rivals (yours or your group's). |
| [Blackjack](packages/Blackjack) | `bj help` | Plays **blackjack** with basic strategy after you `cjoin`, and tracks wins, zenni, Lucky Tails and XP. |
| [VideoPoker](packages/VideoPoker) | `vp help` | Plays the **video poker** machine (Jacks or Better) with the standard strategy, with stop loss / target / hand limits and stats. |
| [HighStakes](packages/HighStakes) | `hs help` | Advice for the Friday **High Stakes** hold'em tournament: win chance, pot odds and a suggested move on your turn; `hs go` sends it. |
| [FriezaQuest](packages/FriezaQuest) | `fq help` | Automates the **Frieza's Spaceship** quest from Appule to the Bridge Access Card. |
| [BossTimer](packages/BossTimer) | `boss help` | Counts down to the **boss respawn** (from `uptime`), warns 5 and 1 minutes before, and re-checks by itself after each respawn. |
| [YamoshiSpawn](packages/YamoshiSpawn) | `ys help` | Runs the three Temple trials and the ritual that **summons Yamoshi**. |

Install only the ones you want, plus **MSDP**: Autolearn, Chores, KaiokenTrain, Score and DataLords2 need it, and Blackjack uses it when it's there. FriezaQuest, YamoshiSpawn, BossTimer, VideoPoker and HighStakes work without it.

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
  Blackjack/ DataLords2/ FriezaQuest/ HighStakes/ VideoPoker/ YamoshiSpawn/  single-script packages
    package.json          version, triggers (patterns + one-line scripts), aliases
    src/<Package>.lua     all the logic, in one Lua table named after its command (bj, dl2, fq, hs, vp, ys)
tests/                    Lua tests for the single-script packages + run.sh for everything
docs/design/               how Autolearn, KaiokenTrain and Chores were extracted from CK
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

- **Blackjack, DataLords2, FriezaQuest, HighStakes, VideoPoker, YamoshiSpawn:** (HighStakes replays a real tournament log from `tests/fixtures/`) Mudlet's API is stubbed and real game output is replayed. YamoshiSpawn walks a model of the temple map, so a wrong turn fails the test.
- **Autolearn, Chores, KaiokenTrain, Score:** each manifest is linted, because muddler silently ships an empty script if a trigger's `.lua` file is missing. Then the real package sources run through a simulated session (connect → MSDP → prompts → the bot).

## Versioning

Every package uses [semantic versioning](https://semver.org/), `MAJOR.MINOR.PATCH`, in its `package.json` or `mfile`:

- **PATCH** (1.2.0 → 1.2.1): bug fixes, e.g. a trigger pattern that missed a line.
- **MINOR** (1.2.0 → 1.3.0): new features or behaviour that existing users won't trip over, e.g. a new command or stage.
- **MAJOR** (1.2.0 → 2.0.0): changes that need users to do something, e.g. a renamed package or command, or settings that no longer carry over.

Autolearn, Chores, KaiokenTrain and Score used date versions (e.g. `26.07.27`) while they lived in the CK repo, and restarted at 1.0.0 here.

## Releasing

Bump the version of each package you changed, commit, then tag:

```bash
git tag v2026.10.21 && git push --tags
```

The release workflow runs every test, builds all eight packages and attaches them to a GitHub release. That's what the install links and the `update` aliases download.

## Credits and license

Autolearn, Chores, KaiokenTrain and Score were extracted from the [CK package](https://github.com/CKMud-Mudlet-Scripts/CK) by Jason Fried ("fried") and extended. Their install and update links now point at this repository. Everything is released under the [Apache 2.0 license](LICENSE), the same as CK.
