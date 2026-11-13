![shenron](src/resources/shenron.png)

# Chores

A standalone Mudlet package for CKMud that automates the boring bits: fishing
and the royal cook delivery quest. Extracted from the
[CK](https://github.com/CKMud-Mudlet-Scripts/CK) ecosystem and fully
self-contained - it does NOT require CK to be installed.

## Installation

`lua installPackage("https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/Chores.mpackage")`

**Requires the [MSDP](../MSDP) package**, which supplies the stats this package reads. Install it first.

After installation the `CH update` alias will take care of updating the script.

You must turn on `msdp` in settings to use this script (the package enforces
the correct protocol settings on connect, same as CK does).

## Usage

Stand at your fishing spot holding a fishing pole, then:

`chores fish` - auto fishing: castout, reelin on a bite, recast, untangle.
When fatigue drops below `chores.rest_below`% - or the mud says "You are too
exhausted to fish right now." - it walks `chores.rest_path`, sleeps, and walks
back via `chores.fishing_path` when rested.

`chores quest` - runs the royal cook delivery every `chores.quest_period`
minutes: travel `chores.cook_path` (default: recall then instant transmission
to Roshi, 3 attempts), pursue the cook,
accept, deliver the jerky to whichever knight he names. If the cook says the
delivery is on cooldown, the next attempt is scheduled for exactly when the
cooldown ends.

`chores both` - quest whenever the cooldown is up, fish in between. The quest
preempts fishing and even resting; fishing resumes afterwards via
`chores.fishing_path`.

`chores off` - stop. Bare `chores` toggles between off and `both`.

Toggling into `quest` or `both` runs the delivery immediately, then settles
into the main loop (fishing between cooldowns in `both`).

A second periodic task, the **gravedigger excavation**, runs in `quest`/`both`
modes once configured (the cook delivery takes priority when both are due):
travel `chores.grave_path` to Billy (default: instant transmission to gine,
then pursue him), `say task` - repeated every few seconds until he answers,
since `pursue` may still be walking -
and when he names a plot ("Yer in luck <name>, plot 4 is ready to be
excavated." - or the nag "I already done told you! I need you to go dig up
burial plot 5!" when the task was already assigned) confirm a shovel with
`locate shovel` - "a wrought iron burial
shovel" means we have one, "No matching items found" buys one from Billy with
`buy 1` - then walk the matching `chores.grave_plot_<n>` route, `dig`, and
return to fishing. Unset `grave_path` disables it with a one-time hint; an
unmapped plot or a timeout aborts cleanly to fishing. The task also needs
1 billion base power level (Billy's requirement, read from MSDP BASE_PL before
travelling) and is skipped with a one-time note below it.

Every quest step has a timeout - if anything unexpected happens the cycle
aborts and the bot returns to fishing rather than idling somewhere odd.

If a cycle ever stalls, `CH feature chores.debug on` traces each step so you
can see exactly where it stopped.

## Constants

Set with `CH constant <name>=<value>`:

- `chores.fishing_path` - commands to reach your fishing spot; used after the
  quest, and after resting, so it should work from both places (e.g. start it
  with a recall)
- `chores.rest_path` - commands from the fishing spot to your rest room
- `chores.cook_path` - commands to reach the royal cook, default
  `recall;focus 'instant' roshi`. Like `grave_path` it may include the
  `pursue royal cook` step, in which case the Roshi confirmation is skipped;
  a travel-only path keeps it (with 3 instant retries)
- `chores.quest_period` - minutes between deliveries, default 5
- `chores.recast_timeout` - seconds without a bite before recasting, default 120
- `chores.rest_below` - fatigue percent that triggers a rest, default 20
- `chores.grave_period` - minutes between gravedigger tasks, default 5
- `chores.grave_path` - commands to reach Gravedigger Billy, default
  `focus 'instant' gine;pursue gravedigger`. It may include the
  `pursue gravedigger` step (as the default does) or just the travel commands,
  in which case the bot adds the pursue itself. Set it to an empty string to
  disable the excavation task.
- `chores.grave_plot_1` ... `chores.grave_plot_7` - movement commands from
  Billy to each plot, pre-filled with working routes
- `chores.boss_before` / `chores.boss_attack` / `chores.boss_after` - boss
  fish fight: commands before, the attack to repeat, commands after
- `chores.rival_before` / `chores.rival_attack` / `chores.rival_after` -
  rival ambush ("<Name> flies out of nowhere and attacks you!"): commands
  before ($target is replaced with the rival's keyword), the attack to repeat
  (the target is appended), commands after the fight. The fight end is
  detected via the kill line/MSDP opponent feed; afterwards an interrupted
  quest resumes at the royal cook (who re-asks or reminds us which knight
  the jerky is for) and anything else resumes via chores.fishing_path.
  With rival_attack unset the bot only warns and leaves the fight to you.

## Boss fish

On "A massive shadow emerges from the depths... Prepare for battle!" the bot
sends `chores.boss_before`, repeats `chores.boss_attack` each tick, and
detects the kill via the MSDP opponent feed; then `chores.boss_after` runs
and casting resumes. With `boss_attack` unset the bot only warns and leaves
the fight to you.

## Development

This is a [muddler](https://github.com/demonnic/muddler) project - run `muddler`
in this directory to produce `build/Chores.mpackage`.

Before building, two checks catch the common failure modes:

```
python3 ../../tools/lint_manifests.py src   # every trigger/alias has a script
cd tests && npm install && node runner.js driver.lua   # simulated Mudlet run
```
