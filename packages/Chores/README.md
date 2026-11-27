# Chores

Command: `chores`

Automates the boring bits of CKMud: fishing, the royal cook delivery quest and the gravedigger
excavation. Originally extracted from the [CK](https://github.com/CKMud-Mudlet-Scripts/CK) package
by fried; it doesn't need CK.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Chores.mpackage")`

**Requires the [MSDP](../MSDP) package** (with MSDP turned on in Mudlet's settings), which supplies
your fatigue, base power level and opponent. Install it first. `chores update` updates Chores.

## Usage

Set your two paths once (they're saved):

```
chores set fishing_path recall;w;w;n     from the rest room, and after a delivery, to the fishing spot
chores set rest_path e;e;u               from the fishing spot to your rest room
```

Then stand at your fishing spot holding a fishing pole and type one of:

| Command | What it does |
|---|---|
| `chores fish` | Fish: `castout`, `reelin` on a bite, cast again, untangle; rest when fatigued |
| `chores quest` | Only the deliveries: the royal cook every 5 minutes and the gravedigger whenever he has a plot |
| `chores both` / `chores start` | The deliveries whenever they're due, fishing in between |
| `chores stop` / `chores off` | Stop |
| `chores status` | What it's doing and when the next deliveries are |
| `chores set` | Every setting with its value |
| `chores set <name> <value>` | Change a setting (saved). `default` puts it back, `off` empties it |
| `chores gumshoe on\|off` | Pause for Gumshoe's `gum repeat` cases (default on, saved) |
| `chores debug on\|off` | Trace every step, for when a cycle stalls |
| `chores update` | Update Chores to the latest release |

`CH` works as well as `chores`. While it runs, the prompt shows `[chores:both/fishing]` (mode and
what it's doing).

### Fishing

On a bite it reels in and casts again. With no bite for `recast_timeout` seconds it casts again.
When fatigue drops below `rest_below`%, or the game says you're too exhausted to fish, it reels in,
walks `rest_path` and sleeps. Once rested it wakes and walks `fishing_path` back. "This is not a
good place to fish" walks `fishing_path` back; three of those without a bite in between stop it.

### The royal cook delivery

Every `quest_period` minutes it travels `cook_path` (by default `recall` and instant transmission
to Roshi, three tries), pursues the royal cook, says yes and gives the jerky to the knight he
names. If he says the last delivery was too recent, it tries again exactly when the wait is over.
A `cook_path` that includes `pursue royal cook` skips the Roshi check.

### The gravedigger

Every `grave_period` minutes (after the cook, who goes first) it travels `grave_path` to
Gravedigger Billy (by default instant transmission to gine, then `pursue gravedigger`) and says
`task` every few seconds until he answers. For the plot he names it checks for a burial shovel
(`locate shovel`, buying one from Billy if needed), walks that plot's `grave_plot_<n>` route,
digs and picks up the loot. He needs 1 billion base power level, which comes from MSDP (type
`score` once if it says it doesn't know yours). `chores set grave_path off` turns the excavation
off.

### Boss fish, rivals and dying

A boss fish ("A massive shadow emerges from the depths...") gets `boss_before`, then `boss_attack`
until it dies, then `boss_after`, and fishing goes on. A rival ("<Name> flies out of nowhere and
attacks you!") gets `rival_before` (`$target` is the rival), `rival_attack <rival>` until the
fight ends, then `rival_after`, and whatever was interrupted carries on: an interrupted delivery
goes straight back to the cook. With `boss_attack` or `rival_attack` empty it only warns and
leaves the fight to you. If you die, it heads back to fishing.

### Pausing for Gumshoe's repeat

With Gumshoe's `gum repeat` on (`gumshoe.xml`), Chores steps aside for every case. Just before
Gumshoe heads to Jaco it reels in or wakes you; a boss fish or rival fight is finished first
(Gumshoe waits for it), and a delivery that was under way is done again afterwards. Once Gumshoe is
back at Jaco after the case, Chores carries on: `fishing_path` back to the spot and fishing again,
or in quest mode just the next delivery. That replaces the `gum repeat wait` commands. Without a
`fishing_path` it stays off after the case and says so. `chores stop` while it's paused keeps it
off, turning Gumshoe's repeat off doesn't walk you anywhere, and `chores gumshoe off` turns all
this off.

Every step of a delivery has a time limit, so anything unexpected sends it back to fishing rather
than leaving it idle somewhere odd.

## Settings

| Setting | Default | |
|---|---|---|
| `fishing_path` | | To the fishing spot, from the rest room and after a delivery (start it with a recall) |
| `rest_path` | | From the fishing spot to the rest room |
| `rest_below` | 20 | Rest below this fatigue % |
| `recast_timeout` | 120 | Seconds without a bite before casting again |
| `cook_path` | `recall;focus 'instant' roshi` | To the royal cook |
| `quest_period` | 5 | Minutes between cook deliveries |
| `grave_path` | `focus 'instant' gine;pursue gravedigger` | To Gravedigger Billy (empty: no excavation) |
| `grave_period` | 5 | Minutes between gravedigger tasks |
| `grave_plot_1` ... `grave_plot_7` | working routes | From Billy to each plot |
| `boss_before`, `boss_attack`, `boss_after` | | Boss fish fight |
| `rival_before`, `rival_attack`, `rival_after` | | Rival fight (`$target` is the rival) |

Settings are saved in `chores.lua` in your profile folder.

## Changes in 3.0

Chores is now one Lua file like the newer packages. `CH constant chores.<name>=<value>` is now
`chores set <name> <value>`, and `CH features` and `CH feature chores.debug on` are now
`chores debug on`. Your 2.x settings are brought over the first time 3.0 loads. A bare `chores`
now shows the help instead of turning it on: use `chores start` or `chores both`. It no longer
changes Mudlet's protocol settings or reconnects by itself, and base PL now comes from the MSDP
package (which reads it from `score`).

## Development

`python3 tools/build.py Chores` builds `dist/Chores.mpackage`, and `lua tests/Chores_test.lua`
(from the repo root) tests it.
