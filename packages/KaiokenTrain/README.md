# KaiokenTrain

Command: `kt`

Trains your kaioken mastery to the top. It raises kaioken just above your mastery, drinks when
you're thirsty, sleeps when you're fatigued, wakes when you're rested, and stops once kaioken is
mastered. Originally extracted from the [CK](https://github.com/CKMud-Mudlet-Scripts/CK) package by
fried; it doesn't need CK.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/KaiokenTrain.mpackage")`

**Requires the [MSDP](../MSDP) package** (with MSDP turned on in Mudlet's settings), which supplies
your fatigue, thirst and the rest. Install it first. `kt update` updates KaiokenTrain.

## Usage

Go to an isolation chamber with something to drink and type `kt start` (or `kaioken train`, which
turns it on and off). `kt stop` stops it.

| Command | What it does |
|---|---|
| `kt` / `kt help` | The commands, and the current drink and room |
| `kt start` | Start training |
| `kt stop` | Stop |
| `kt status` | Training or not, your kaioken, mastery and the ceiling |
| `kt drink <command>` | What to drink when thirsty, default `drink tears` (saved) |
| `kt room <0-10>` | Extra levels above mastery + 9, default 2 (saved) |
| `kt back <commands>\|off` | After a Gumshoe repeat case: from Jaco back to your training spot (saved) |
| `kt gumshoe on\|off` | Pause for Gumshoe's `gum repeat` cases (default on) |
| `kt update` | Update KaiokenTrain to the latest release |
| `kaioken train` | Turn training on or off |

While it trains, the prompt shows `[kt training][x21 / x10]` (kaioken / mastery).

### How high it trains

Kaioken mastery only climbs to 8 below the kaioken you're using, so mastery + 9 leaves room for
one point per gain. With Accelerated Mastery (`pshop mastery`) one gain can land 2 or 3 points, so
it trains at mastery + 9 + the room (default 2, i.e. mastery + 11). A higher level drains fatigue
faster, so without the perk use `kt room 0`.

If the game won't hold the level it asks for (it asks three times), it steps down one level for
the rest of the session and says so.

The last stretch is different: once mastery + 9 + the room reaches your ceiling (`kaioken getmax`,
e.g. 128), it trains at the ceiling itself and never steps down, until mastery is 8 below it (120).
Before it stops it asks `kaioken getmax` again, because the ceiling grows as you do; if it grew,
training goes on.

Each start reads your mastery fresh (from the prompt or `status`), so a value left over from
another character or a rebirth can't make it think kaioken is already mastered.

### Pausing for Gumshoe's repeat

With Gumshoe's `gum repeat` on (`gumshoe.xml`), training steps aside for every case. Just before
Gumshoe heads to Jaco it stops training, drops your kaioken and wakes you if you're asleep. Once
Gumshoe is back at Jaco after the case, it sends your `kt back` commands (your aliases work too,
`;` between them), for example `kt back crecall;w`, and starts training again. That replaces the
`gum repeat wait` commands. Without `kt back` set, training stays off after the case and it says
so. `kt stop` while it's paused keeps it off, turning Gumshoe's repeat off doesn't walk you
anywhere, and `kt gumshoe off` turns all this off.

## Changes in 3.0

KaiokenTrain is now one Lua file like the newer packages. `KT`, `KT features` and
`KT constant ...` are gone. The two settings are `kt drink` and `kt room`, saved in
`kaiokentrain.lua` in your profile folder. Settings from 2.x aren't carried over, so set them again
if you had changed them. It no longer changes Mudlet's protocol settings or reconnects by itself;
it tells you if MSDP is off.

## Development

`python3 tools/build.py KaiokenTrain` builds `dist/KaiokenTrain.mpackage`, and
`lua tests/KaiokenTrain_test.lua` (from the repo root) tests it.
