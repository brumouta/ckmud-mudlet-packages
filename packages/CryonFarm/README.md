# CryonFarm — Confession of Cryon Frigidus

Command: `cryon`

Farms the **Confession of Cryon Frigidus** from the hidden lab under the Zero Nexus Research Facility on Iceria. You need the **Hidden Laboratory Access Card** (it opens the Hidden Hallway) and the **Needleless Syringe** (for `extract`). Type `cryon start` from anywhere.

## Commands

| Command | Effect |
|---|---|
| `cryon start` | Do the whole run. Refuses if you already farmed since the last respawn; `cryon start force` goes anyway |
| `cryon stop` | Stop |
| `cryon resume` | Carry on from the step it stopped at. Sort things out by hand first |
| `cryon attack <cmd>` | What kills an Electromagnetic Field (default `fg f`) |
| `cryon status` | The step it's on and confessions this session |

## The run

1. `it innkeeper` to the Blizzards Edge Inn, then `s e e s s e e e e` along Commerce Way to Frost Plaza.
2. `n n` up the snow covered path to the Research Facility, then `n n n n n` to the dead-end Atrium. The access card opens the **Hidden Hallway** and moves you in.
3. Through the Hidden Laboratory ring to the **Incubation Chamber**, where a trapdoor drops you into the lower lab. Then `e e e e d` to the **Control Room**.
4. **Pyrokinetic chamber** (north-east): `extract` from the citizen in the centre, then leave south straight away (the Fire Fields burn).
5. **Electromagnetic chamber** (south-east): kill the **Electromagnetic Field** in each of the four rooms around the centre. An Elite Icerian Mercenary charges in each time, and auto-combat kills it. The fourth field shatters the barrier; then `extract` in the centre.
6. **Cryogenic chamber** (south-west): `extract` frees the citizen from stasis, then takes the sample.
7. **Genetic Amplification chamber** (north-west): wait for *How..did...I..get here?*, `say kidnapped`, wait for *"SMACK" him awake*, `smack citizen`. Cryon Frigidus hands over the confession.

The citizens only come back with the respawn (the one `uptime` counts down to), so it's one confession per respawn. With the [BossTimer](../BossTimer) package installed it tells you after each confession how long until the next one. The Mad Scientist in the Control Room is a different quest (it uses the samples) and is ignored.

Moves between stops go out together (the same as typing `n;;n;;e`), and every room that comes back is checked against the route. Each step waits for the room it expects (or the game's answer) and stops with a message if it doesn't come. The route is fixed, from one run in the log. If a move ends up somewhere unexpected, the room list in `C.ROUTE` needs updating.
