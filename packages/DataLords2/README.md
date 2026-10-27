# DataLords2 — Data Lords v2.0 event automation

For the **Data Lords v2.0** event only, not Data Lords 1 or 3. It only switches on for `The Data Lords v2.0 event has been requested by <you>.`, so it stays off during the other two events.

Command: `dl2`

Runs the Data Lords v2.0 boss chain, but only for an event **you** requested, and handles rivals along the way.

## Commands

| Command | Effect |
|---|---|
| `dl2 help` | List the commands |
| `dl2 status` | Event state, current boss, live rivals, attack, loop |
| `dl2 loop [on\|off]` | When Zenzeyh dies: always `get all.tab`; with the loop on, also `request event 18` 7 seconds later (within the token limit) |
| `dl2 tokens` | Tokens spent this session and in past sessions |
| `dl2 tokens reset` | Start a new session count now |
| `dl2 limit <n>\|off` | Per-session token limit for the loop, e.g. `dl2 limit 200k` (default 100,000) |
| `dl2 attack <cmd>` | Attack used on bosses and rivals (default `ss`) |
| `dl2 resume` | Forget pending rivals and continue the pursuit |
| `dl2 off` | Stop the event automation now |

## How it works

- **Gate:** `The Data Lords v2.0 event has been requested by X.` turns the `dl2 Bosses` trigger folder on when X is you, and off otherwise. Your name comes from the [MSDP](../MSDP) package (from `score`, since the MUD no longer sends it over MSDP). Until it's known, DataLords2 uses a saved name: set it with `dl2 name <you>`, or it's learned when the request line follows your own `request event`. The Zenzeyh end line turns it off.
- **Bosses:** each boss's announcement or death starts the next one. For the location-based bosses it sends `event`, reads `Location: <planet>`, uses the travel commands for that planet (`dl2.travel` at the top of the script) and then `pursue` / attack. Built for speed: nothing waits that doesn't have to (see below).
- **Jhet and Macubyree** always stand together. After travelling, the bot sends `pursue jhet`, then attacks Macubyree. Once he's dead ("Macubyree is dead!") it attacks Jhet in the same room, without pursuing again. Once both are dead it waits for the next boss. If someone kills Jhet first, Macubyree dies with him, so the pair is done and it goes to Weezpurr as soon as her start line appears (straight away if it already has). It never sends `pursue macub`, which can find Macubyree demonspawn (a different mob).
- **Waiting for rivals:** a boss's start line during a rival fight is queued until every rival is dead, and then the bot goes. Your MSDP target isn't used for this, because it can still show an old opponent long after a fight. If some other fight makes the instant fail, the `look` check notices and the bot travels again a second later.
- **Checking the travel worked:** after every `focus 'instant' <npc>` (malak, dende, gine, innkeeper, minotia or joe), the bot sends `look <npc>` and, without waiting for the answer, the rest of the route and the attack. "Gine is in excellent condition." means it worked; "You do not see that here." means the instant failed, and the bot asks `event` and travels again. 10 seconds after attacking a boss, the boss must also be your MSDP target, otherwise it travels again too. After 10 failed tries it stops and says so; `dl2 resume` makes it travel again.
- **Loot:** `get all.tab` after every boss (Macubyree, Jhet, Weezpurr, Phenix, Daiue, Zenzeyh), before going anywhere.
- **After Macubyree:** attack Jhet straight away, plus `look jhet`; if he isn't there, `pursue jhet` and attack again.
- **Loop:** 5 seconds after Zenzeyh dies it sends `request event 18`. On "There is already an event running" it tries again every second (up to 60 times).
- **Rivals:** `... flies out of nowhere and attacks <you|name>!` and `The sky splits open as ... crashes down upon <you|name> ...` pause the attacking (boss lines are still recorded, so nothing is missed). Every rival seen is tracked, and the pursuit resumes only once all of them are dead (`... is dead!  R.I.P.`).

**Requires the [MSDP](../MSDP) package**, which also subscribes to `COMBO_HISTORY` for your daze triggers.

## Token spending

Each Data Lords v2.0 request costs **10,000 tokens**. Every event **you** request, by hand or through `dl2 loop`, is recorded against the current **session**. A new session starts each time you connect; the spending is saved in your profile, so reloading the package doesn't lose it, and the last 20 sessions are kept (`dl2 tokens`).

Before `dl2 loop` re-requests the event, it checks the session's **limit** (default 100,000, i.e. 10 events). If another request would go over it, or MSDP shows you have fewer than 10,000 tokens, the loop turns itself off and says why. `dl2 limit 200k` raises it, `dl2 limit off` removes it, and `dl2 tokens reset` starts the count over.
