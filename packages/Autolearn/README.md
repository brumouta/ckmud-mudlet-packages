![shenron](src/resources/shenron.png)

# Autolearn

A standalone Mudlet package for CKMud that masters all your skills, and learns
new skills once you have mastered their prerequisites. Extracted from the
[CK](https://github.com/CKMud-Mudlet-Scripts/CK) package and fully
self-contained — it does NOT require CK to be installed.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Autolearn.mpackage")`

**Requires the [MSDP](../MSDP) package**, which supplies the stats this package reads. Install it first.

After installation the `AL update` alias will take care of updating the script.

You must turn on `msdp` in settings to use this script (the package enforces
the correct protocol settings on connect, same as CK does). Also while you are
there disable MSSP and GMCP.

## Usage

`autolearn <target> <speedwalk_to_isolation>` - Start the auto learn process using
<target> to train every skill until its mastered. Androids can ignore the
speedwalk argument. Run `autolearn` again to turn it off.

The following constants should be used by organics

1. `learning.recall_isolation` this will get you to an isolation tank from any location on the mud. Mine is "recall;s;w;enter vort;s"
2. `learning.return_to_target` this will get you back to the original target from anywhere (it should start from your recall point). Mine is "crecall;n;n;n;e;n" this will change based on target

Set them with e.g. `AL constant learning.return_to_target="crecall;n;n;n;e;n"`

When BOTH constants are set, the bot rests by running the recall_isolation
path (which works from any room) and walks back with return_to_target — and
the `<speedwalk_to_isolation>` argument becomes optional. Without them it
falls back to speedwalking the path you gave and reversing it, which assumes
the bot is standing at the target. Training `portal`/`instant transmission`
teleports you to king kai and is only attempted when `return_to_target` is
set, so the failed-attack trigger can walk you back.

The bot needs to know your skills and race: it sends `learn` and `score` when
it sees the MOTD, and again when you toggle `autolearn` on. If your race shows
as `???`, type `score` once.

## Aliases

`autolearn <target> <speedwalk>` - toggle auto learning

`AL` - get a list of Autolearn commands

`AL features` - list feature flags

`AL feature <name> <on|off>` - turn a feature on/off (e.g. `learning.use_zeta`)

`AL constants` - list script constants (these survive resetProfile())

`AL constant <name>=<value>` - set a script constant

`AL update` - update Autolearn from github latest

## Running alongside CK

Autolearn keeps all of its state under its own `AL` global namespace, its own
`Autolearn` settings database, and its own `AL.*` events, so it will not
corrupt an installed CK package. If you do run both, note that each package
parses the prompt and MOTD independently (you may see doubled login commands),
and you should use CK's own `autolearn` OR this package — not both at once.
Recent CK versions no longer ship the autolearn feature.

## Development

This is a [muddler](https://github.com/demonnic/muddler) project — run `muddler`
in this directory to produce `build/Autolearn.mpackage`.

Before building, two checks catch the common failure modes:

```
python3 ../../tools/lint_manifests.py src   # every trigger/alias has a script
cd tests && npm install && node runner.js driver.lua   # simulated Mudlet run
```

The tests run the real package sources in a Lua VM with a stubbed Mudlet API
and simulate connect → MSDP feed → score/learn parsing → prompt →
`autolearn` toggle → bot attack/rest/wake cycle.
