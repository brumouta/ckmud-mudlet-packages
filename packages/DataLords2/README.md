# DataLords2 — Data Lords v2.0 event automation

For the **Data Lords v2.0** event only, not Data Lords 1 or 3. It only switches on for `The Data Lords v2.0 event has been requested by <you>.`, so it stays off during the other two events.

Command: `dl2`

Runs the Data Lords v2.0 boss chain, but only for an event **you** requested, and handles rivals along the way.

## Commands

| Command | Effect |
|---|---|
| `dl2 help` | List the commands |
| `dl2 status` | Event state, current boss, live rivals, attack, loop |
| `dl2 loop [on\|off]` | Re-request the event (`req event 18`) 7 seconds after Zenzeyh dies |
| `dl2 attack <cmd>` | Attack used on bosses and rivals (default `ss`) |
| `dl2 resume` | Forget pending rivals and continue the pursuit |
| `dl2 off` | Stop the event automation now |

## How it works

- **Gate:** `The Data Lords v2.0 event has been requested by X.` turns the `dl2 Bosses` trigger folder on when X is you, and off otherwise. Your name comes from the [MSDP](../MSDP) package (from `score`, since the MUD no longer sends it over MSDP). Until it's known, DataLords2 uses a saved name: set it with `dl2 name <you>`, or it's learned when the request line follows your own `req event`. The Zenzeyh end line turns it off.
- **Bosses:** each boss's announcement or death starts the next one. For the location-based bosses it sends `event`, reads `Location: <planet>`, uses the travel commands for that planet (`dl2.travel` at the top of the script) and then `pursue` / `sense` / attack.
- **Rivals:** `... flies out of nowhere and attacks <you|name>!` and `The sky splits open as ... crashes down upon <you|name> ...` pause the boss triggers. Every rival seen is tracked, and the pursuit resumes only once all of them are dead (`... is dead!  R.I.P.`).

**Requires the [MSDP](../MSDP) package**, which also subscribes to `COMBO_HISTORY` for your daze triggers.
