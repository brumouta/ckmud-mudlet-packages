![shenron](src/resources/shenron.png)

# Autolearn

A standalone Mudlet package for CKMud that masters all your skills, and learns
new skills once you have mastered their prerequisites. Extracted from the
[CK](https://github.com/CKMud-Mudlet-Scripts/CK) package and fully
self-contained - it does NOT require CK to be installed.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Autolearn.mpackage")`

**Requires the [MSDP](../MSDP) package**, which supplies the stats this package reads. Install it first.

After installation the `AL update` alias will take care of updating the script.

You must turn on `msdp` in settings to use this script (the package enforces
the correct protocol settings on connect, same as CK does). Also while you are
there disable MSSP and GMCP.

## Usage

`autolearn <target> <path>` - Start the auto learn process using <target> to
train every skill until it's mastered. `<path>` is the walk from the target to
your rest spot (an isolation tank), e.g. `autolearn elder n;n;n;n;w`. Androids
can leave it out. Run `autolearn` again to turn it off.

**The way back comes from that path:** `crecall`, then the path backwards with
every step reversed. `autolearn elder n;n;n;n;w` walks back with
`crecall;e;s;s;s;s`, and prints it when it starts. It's used after resting,
after training portal/instant transmission (they teleport you to king kai), and
when the target isn't there. A path with a step that isn't a direction
(`enter vort`) can't be walked back, so then portal/instant aren't trained.

The path takes `;`, commas, spaces or counts (`n;n;n;n;w`, `n n n n w`,
`4n w`). Type it with a single `;`: Mudlet splits what you type at `;;` before
the alias sees it, so `autolearn elder n;;n;;w` would send the `n`s as moves.

To rest, the bot walks the path to the tank and back. Or set
`learning.recall_isolation` to a way to the tank that works from any room
(mine is `crecall;w`) and it uses that instead:
`AL constant learning.recall_isolation="crecall;w"`.

The bot needs to know your skills and race: it sends `learn` and `score` when
it sees the MOTD, and again when you toggle `autolearn` on. If your race shows
as `???`, type `score` once.

### What it trains first

By default ki attacks come first, then fatigue attacks, AoE, buffs, heals, ultras, then the
other skills (powersense, multiform, scan, instant, ...). Whatever you can't afford right now
waits while the others train. To train some skills first, list them in order:

`AL priority multiform, kamehameha, roundhouse` (`AL priority` shows the list, `AL priority clear` empties it)

Names are the ones `learn` shows (or the short command, `kame`). Spaces don't matter (`power up` = `powerup`).
When you set it, each name is checked against your skills and any that isn't one is
reported, with the closest match (`Not one of your skills: 'multifrom' - did you mean 'multiform'?`). A priority skill you can't
afford yet waits, and the others keep training meanwhile.

Multiform is trained with `focus 'multiform'` followed by `order followers dismiss`, so no
clones pile up (that also dismisses any other followers you have).

## Aliases

`autolearn <target> <speedwalk>` - toggle auto learning

`AL` - get a list of Autolearn commands

`AL features` - list feature flags

`AL feature <name> <on|off>` - turn a feature on/off (e.g. `learning.use_zeta`)

`AL constants` - list script constants (these survive resetProfile())

`AL constant <name>=<value>` - set a script constant

`AL priority [skills|clear]` - skills to train first, in order (e.g. `AL priority multiform, kamehameha`)

`AL update` - update Autolearn from github latest

## Running alongside CK

Autolearn keeps all of its state under its own `AL` global namespace, its own
`Autolearn` settings database, and its own `AL.*` events, so it will not
corrupt an installed CK package. If you do run both, note that each package
parses the prompt and MOTD independently (you may see doubled login commands),
and you should use CK's own `autolearn` OR this package - not both at once.
Recent CK versions no longer ship the autolearn feature.

## Development

This is a [muddler](https://github.com/demonnic/muddler) project - run `muddler`
in this directory to produce `build/Autolearn.mpackage`.

Before building, two checks catch the common failure modes:

```
python3 ../../tools/lint_manifests.py src   # every trigger/alias has a script
cd tests && npm install && node runner.js driver.lua   # simulated Mudlet run
```

The tests run the real package sources in a Lua VM with a stubbed Mudlet API
and simulate connect -> MSDP feed -> score/learn parsing -> prompt ->
`autolearn` toggle -> bot attack/rest/wake cycle.
