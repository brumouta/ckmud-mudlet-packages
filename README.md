# CKMud Mudlet Packages

Self-contained [Mudlet](https://www.mudlet.org/) packages for CKMud: bots, event and quest automation, and a better score sheet. None of them need the CK package installed.

| Package | Command | What it does |
|---|---|---|
| [MSDP](packages/MSDP) | `msdp` | **Install this first.** Subscribes to every MSDP variable CKMud offers and shares the values (plus your name, race and base PL from `score`) with the packages below. |
| [Autolearn](packages/Autolearn) | `al help` | Masters all your skills and learns new ones once their prerequisites are mastered. |
| [Chores](packages/Chores) | `chores` | Automates fishing, the royal cook delivery quest and the gravedigger excavation. |
| [KaiokenTrain](packages/KaiokenTrain) | `kt` | Trains kaioken to max mastery: raises it step by step, drinks, rests and stops when mastered. |
| [Score](packages/Score) | `score`, `sc` | A richer `score`: real numbers, damage at every boost level, item tier progress, training hints. |
| [DataLords2](packages/DataLords2) | `dl2 help` | Runs the **Data Lords v2.0** event boss chain (not Data Lords 1 or 3) when *you* requested it, pausing for rivals (yours or your group's). |
| [Casino](packages/Casino) | `casino` | The **Lucky Monkey Casino**: plays **blackjack** (`bj`), **video poker** (`vp`) and **slots** (`slot`), and advises in the Friday **High Stakes** hold'em tournament (`hs`). Tracks zenni, Lucky Tails and XP. |
| [FriezaQuest](packages/FriezaQuest) | `fq help` | Automates the **Frieza's Spaceship** quest from Appule to the Bridge Access Card. |
| [BossHelpers](packages/BossHelpers) | `boss help` | Counts down to the **boss respawn** (from `uptime`), warns 5 and 1 minutes before, and re-checks by itself after each respawn. |
| [YamoshiSpawn](packages/YamoshiSpawn) | `ys help` | Runs the three Temple trials and the ritual that **summons Yamoshi**. |
| [MoroQuest](packages/MoroQuest) | `moro help` | The Moro questline: decodes Merus's **prisoner manifest** and posts the **wanted bulletins** at all five spaceports. |
| [Buffs](packages/Buffs) | `autobuff help`, `buffwnd` | *By Penguin.* Keeps your buffs up, recasting each as it wears off, with a timer window. |
| [Chat](packages/Chat) | `chatwnd` | *By Penguin.* A tabbed chat window for OOC, tells, group, auctions, events and says. |
| [Health](packages/Health) | none | *By Penguin.* Your current and max powerlevel from MSDP, for other scripts (`HP`). |
| [Majerska](packages/Majerska) | `maj help` | Travels to **Majerska's Cursed Canopy** on Earth and kills every boss there, weakest first. |
| [Cumber](packages/Cumber) | `cumber help` | Does **Chief Rusk's containment assignment** on the Prison Planet: the records, both plates, the vent and the three load cards at the rig. |
| [FusionQuest](packages/FusionQuest) | `fus help` | Runs the **West Capital fusion questline**: Doberman's capsules, the Red Ribbon factory, Bulma's jobs, Tongari Tower and Hatchiyack, then King Kai and the dance drills. |
| [Gumshoe](packages/Gumshoe) | `gum help` | Solves Jaco's **Briefs mansion** party cases: walks the house, searches, questions, opens the sealed rooms and names who did it. |
| [CryonFarm](packages/CryonFarm) | `cryon help` | Farms the **Confession of Cryon Frigidus** in Iceria's hidden lab: the four DNA samples, the fields and the smack. |
| [Gogeta](packages/Gogeta) | `gog help` | Loops **Kami's timeline portal**: counts your Essences and Diamonds, hands them to Kami, kills SSJ4 Goku, SSJ4 Vegeta and Gogeta, fights off rivals, repeats. Also buys Essences from the event shop. |

Install only the ones you want, plus **MSDP**: Autolearn, Chores, KaiokenTrain, Score and DataLords2 need it, and Casino uses it when it's there. FriezaQuest, YamoshiSpawn, BossHelpers, Gumshoe, CryonFarm, Gogeta, MoroQuest, Majerska, Cumber and FusionQuest work without it.

## Installing

Paste this into Mudlet's input line, replacing `<Package>` with a name from the table (it is case-sensitive, e.g. `Score` or `FriezaQuest`):

```
lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/<Package>.mpackage")
```

Or download the `.mpackage` from the [latest release](../../releases/latest) and use **Toolbox → Package Manager → Install**.

## Updating

Every package has an update command: its command followed by `update`, e.g. `maj update`, `al update`, `sc update`, `chores update`, `kt update`, `casino update`, `autobuff update`, `chatwnd update` or `health update`. It downloads the package from the latest release first and only then swaps it in, so if the download fails (offline, or the repository isn't public) your installed copy stays as it is. Older copies installed as `dl2` or `gumshoe` are replaced too. The shared code is [tools/shared/CKMudUpdate.lua](tools/shared/CKMudUpdate.lua).

## Repository layout

There are two kinds of package, built differently:

```
packages/
  Buffs/ Chat/ Health/     Penguin's packages, in muddler's layout (built without muddler)
    mfile                 name, version, author
    src/                  triggers/aliases/scripts as muddler-style JSON + .lua files, resources/ bundled as is
  BossHelpers/ Casino/ CryonFarm/ DataLords2/ FriezaQuest/ Gogeta/ Gumshoe/ MSDP/ Majerska/ MoroQuest/ Cumber/ FusionQuest/ KaiokenTrain/ Chores/ Score/ Autolearn/ YamoshiSpawn/  single-script packages
    package.json          version, triggers (patterns + one-line scripts), aliases, scripts
    src/<Package>.lua     the logic, in one Lua table named after its command (boss, cryon, dl2, fq, gog, gum, msdp, ys, kt, chores, sc)
    Autolearn/src/        the AL namespace split over several scripts (Base.lua, Learning.lua, Lines.lua, ...)
    Casino/src/           Core.lua (shared casino code) + one script per game (bj, vp, slot, hs)
tests/                    Lua tests for the single-script packages (Autolearn's is a whole simulated session) + run.sh for everything
docs/design/               how Autolearn, KaiokenTrain and Chores were extracted from CK
tools/
  build.py                builds every package into dist/
  muddle.py               the muddler-layout half of build.py (no muddler or Java needed)
  lint_manifests.py       checks every muddler trigger/alias actually has a script
  plugin/                 build-plugin.cjs (copied from CKMud-2D-Desktop): <Pkg>-plugin/ folders -> dist/<pkg>.xml for the CKMud client
```

## Building

Python 3 only, for both kinds of package:

```bash
python3 tools/build.py          # all of them -> dist/
python3 tools/build.py FriezaQuest    # just one
```

The packages with an `mfile` keep [muddler](https://github.com/demonnic/muddler)'s project layout, but [tools/muddle.py](tools/muddle.py) builds them, so neither muddler nor Java is needed. It covers the muddler features these packages use and stops the build on any other, so nothing is dropped silently. Its output was checked against muddler 1.1.0's for all seven packages that used it then: the same triggers, aliases, scripts and bundled files. Only Penguin's Buffs, Chat and Health still use that layout.

## Testing

```bash
sh tests/run.sh
```

Needs Lua 5.3+, Python 3 and Node (Node only builds the CKMud client plugins; those are skipped without it). What it covers:

- **Blackjack, CryonFarm, DataLords2, FriezaQuest, Gumshoe, HighStakes, VideoPoker, YamoshiSpawn:** (HighStakes replays a real tournament log from `tests/fixtures/`) Mudlet's API is stubbed and real game output is replayed. YamoshiSpawn walks a model of the temple map, so a wrong turn fails the test. Gumshoe reads a real case and runs a whole one in a fake Briefs house. CryonFarm does a whole run in a fake lab built from the log's exits.
- **Autolearn:** the real package sources run through a simulated session (connect → MSDP → score and learn sheets → prompts → the bot).
- **KaiokenTrain, Chores, Score:** real game lines through each package's line reader, and each bot's loop.
- **Buffs, Chat, Health:** each manifest is linted (every trigger and alias needs a script; `tools/muddle.py` refuses to build without one too).

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

The release workflow runs every test, builds every package and attaches them to a GitHub release. That's what the install links and the `update` aliases download.

## Credits and license

Autolearn, Chores, KaiokenTrain and Score were extracted from the [CK package](https://github.com/CKMud-Mudlet-Scripts/CK) by Jason Fried ("fried") and extended. Their install and update links now point at this repository. Everything is released under the [Apache 2.0 license](LICENSE), the same as CK.
