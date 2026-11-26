# Cumber

Does **Chief Rusk's containment assignment** on the Prison Planet, start to finish: the test that
lets you into Cumber's Confinement. Type `cumber help`.

| Command | What it does |
|---|---|
| `cumber start` | The whole assignment (500,000 zenni and 40 tokens from Rusk) |
| `cumber solve` | Standing at the workshop rig: just solve the load cards |
| `cumber travel <cmds>` | Gets you to space before `pursue rusk`, `;`-separated (default `crecall;leave`, saved; `off` skips it) |
| `cumber attack <cmd>` | Attack used on rivals (default `de`, saved) |
| `cumber stop` | Stop |
| `cumber update` | Update Cumber to the latest release |

You need Rusk's test coupler.

## How it works

1. **Rusk:** `crecall` and `leave` into space (the clan hall is Galactic Federation HQ), then `pursue rusk`, `say containment`, then
   `look testcoupler` for the card the coupler is on (a fresh one says to study the records first).
2. **Card 1, the prep:** `study containment` in Containment Records, `read west plate` at Western Coil
   Access, `read east plate` at Eastern Coil Access, `inspect cooling loop` and `vent coupler` at
   Northern Cooling Walk, then on to the Restraint Workshop. If the coupler is already on card 2 or 3
   it goes straight to the workshop.
3. **The rig:** each card asks for load units ("Card 1 calls for west 6 load units and east 12").
   A west notch gives 2 units and an east notch 3 (the plates say so; it reads them). So it sends
   `calibrate west 3`, `calibrate east 4`, `loadtest coupler`, and the same for cards 2 and 3.
   A failed test starts again at card 1; it retries up to 3 times.
4. **Back to Rusk:** `say coupler` hands it in.

A rival that "flies out of nowhere and attacks you" gets the attack; once it's dead the step it
interrupted is done again.
