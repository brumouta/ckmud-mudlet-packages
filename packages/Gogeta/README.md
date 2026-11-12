# Gogeta — Kami's timeline portal, on a loop

Command: `gog`

Each round:

1. `pursue kami`, then `say yes`. Kami takes one **Essence from a Dying Star** and one **Celestial Diamond Gemstone** and opens the portal.
2. When SSJ4 Vegeta says *What a waste of my time*, both have landed: `pursue goku`, then `de goku`.
3. When one of them dies, it attacks the other (`de vegeta` or `de goku`).
4. When they fuse (*standing before you is SSJ Gogeta*), `pursue gogeta` (he sometimes walks off), then `de gogeta` until SSJ4 Gogeta dies.
5. Back to Kami for the next round.

Drops that end in **(Celestial)** are picked up as they fall, by the last word of their name (*SSJ4 Gogeta's explosive red aura (Celestial)* → `get aura`). Everything else (Legendary drops, loot boxes, plain halos and tails) is left on the ground.

## Commands

| Command | Effect |
|---|---|
| `gog start [n]` | Start the loop; with `n`, stop after n rounds |
| `gog stop` | Stop |
| `gog attack <cmd>` | Attack sent as `<cmd> <target>` (default `de`, death beam) |
| `gog buy <n>` | Buy n Essences from a Dying Star from the event shop. It reads `eshop` first, because the item numbers change with each event, and never buys more than your event points cover |
| `gog status` | Phase, rounds done and the attack |

## When it stops by itself

- Kami doesn't take the items within 15 seconds of `say yes` (you've run out of Essences or Diamonds).
- Goku and Vegeta don't land within 30 seconds, or a pursue can't sense them after 5 tries.
- A fight goes 3 minutes without a kill.

Celestial Diamond Gemstones can't be bought: they drop from bosses, so the Diamonds you have set how many rounds you can run.
