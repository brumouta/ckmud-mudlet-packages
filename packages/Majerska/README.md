# Majerska

Clears **Majerska's Cursed Canopy** on Earth: travels there, reads the boss list and kills every
boss, weakest first. Type `maj help`.

| Command | What it does |
|---|---|
| `maj go` | Travel to the Canopy and kill every boss |
| `maj kill` | Already inside: read `where` and kill every boss |
| `maj attack <cmd>` | Attack used on bosses and rivals (default `de`) |
| `maj stop` | Stop |

## How it works

1. **Getting there:** `recall`, `press button` (the Zeno Button to the Grand Atrium), `s`, `s`,
   `enter vortex` to Earth, then `survey`. It takes Majerska's Cursed Canopy's number from the list,
   flies there with `survey <n> fly` and `enter`s.
2. **The bosses:** `where` lists them (`[B][powerlevel]Name - Majerska's Cursed Canopy: Room`).
   They're sorted by powerlevel, weakest first.
3. **Each boss:** `pursue <first name>`, then `<attack> <first name>`, until "<Name> is dead!".
   If it moves away ("... who?") it pursues it again. If it can't be found 3 times, or is still
   alive after 5 minutes twice, it's skipped.
4. **When the list is done** it checks `where` again and kills anything still there. It stops
   when nothing is left and says how many died and which were skipped.

A rival that "flies out of nowhere and attacks you" gets the attack too. Once it's dead, the
boss is pursued again.
