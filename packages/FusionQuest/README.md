# FusionQuest

Runs the **West Capital questline** that ends in the Metamoran fusion dance, stage by stage. Type
`fus help`, then `fus start`. The stage is saved, so `fus start` always carries on where it stopped.

| Command | What it does |
|---|---|
| `fus start` | Run from the current stage |
| `fus status` / `fus stages` | The current stage / all of them |
| `fus stage <name>` | Jump to a stage |
| `fus attack <cmd>` | Attack used on quest enemies (default `k`, saved) |
| `fus otherworld <cmds>` | Gets you above King Kai's planet for the survey (default `recall;fly;fly`) |
| `fus stop` | Stop |
| `fus update` | Update FusionQuest to the latest release |

## The stages

| Stage | What happens |
|---|---|
| case | To West Capital (recall, Zeno Button, Earth vortex, survey), `pursue doberman`, `say case` |
| crates | The Underground Market: `inspect crate` in North Stalls, Smugglers' Corner, South Stalls |
| courier | Up the market stairs: fight the courier |
| factory | Warehouse Bay 9: the foreman, the lift, `free engineer` on lines B, C, A and `shut panel` in each booth |
| androids | The Core: `pull breaker`, Androids 15, 14 and Super 13 |
| doberman | Report to Chief Doberman |
| bulma | `say sixteen`, `say air` |
| air | Dr. Briefs `say air`, then `read monitor` at the Plaza Fountain, Dream Land, the hospital garden, North Quad |
| parts | `search` in Capsule Vault, Capsule Storage and the Tool Crib under Bay 9 |
| gas | `say gas` (mask), the drain under Eastside Avenue, the Tuffle war drone, `collect sample`, back to Bulma |
| bench | Waits for Bulma's bench (about 3 minutes), walks out and back in until she hands over Capsule 211 |
| birds | `listen` with Sixteen in the Briefs garden, the Plaza Garden and Dream Land |
| tower | `throw 211 n` at Tongari Tower, the four ghost valves (Turles, Slug, Cooler, Frieza), Hatchiyack, then `get all` for his loot |
| report | Tell Bulma |
| archive | `watch` Goku's recording in the Blueprint Archive |
| somen | The Otherworld Tournament Arena |
| kaikai | King Kai: `focus 'instant' king kai` (if it fails twice: `crecall`, `leave`, `pursue king kai`), then `laugh`, out and back in, the dance he calls |
| gravity | `drill` in Gravity Room South, answering every call |
| hangar | `drill` in the hangar opposite Sixteen |
| done | Fuse with another player (10 billion base PL, knows the dance), then walk into Bulma's workshop fused |

It waits for every room before the next move, never moves during a fight, and attacks each quest
enemy until it's dead (attacking again if a fight stops). If a room or an answer isn't what it
expects, it stops and says so; `fus start` tries that stage again.
