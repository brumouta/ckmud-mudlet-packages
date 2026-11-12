# Gogeta — Kami's timeline portal, on a loop

Command: `gog`

## Before it starts

`gog start` first runs `inventory` and `materials` and counts your **Essences from a Dying Star** and **Celestial Diamond Gemstones**. Each round uses one of each, so it runs as many rounds as the smaller count allows (or fewer, with `gog start <n>`). With none of either it doesn't start. Each finished round shows what's left, and it stops by itself when you run out. `gog check` only counts.

## Each round

1. `pursue kami`, then `say yes`. Kami takes one Essence and one Diamond and opens the portal.
2. When SSJ4 Vegeta says *What a waste of my time*, both have landed: `sense goku`, then `de goku`.
3. When one of them dies, it attacks the other (`de vegeta` or `de goku`).
4. When they fuse (*standing before you is SSJ Gogeta*): `sense gogeta`, then `de gogeta` until SSJ4 Gogeta dies.
5. Back to Kami.

Getting to the bosses:

- **Sense, not pursue.** Bosses wander off, so they're reached with `sense`. If *You lose your concentration*, it senses again (up to 5 tries). If *You can't seem to sense … from here*, it falls back to `pursue`.
- **Bosses that move.** If Goku, Vegeta or Gogeta *leaves* or *flies* somewhere mid-fight, it senses them again and keeps attacking.

**Rivals.** When a rival crashes down on you (*The sky splits open as … crashes down upon you* or *… flies out of nowhere and attacks you*), the round pauses. It attacks the rival, and once every rival is dead it picks up where it was: back to Kami, back to Goku and Vegeta, or after Gogeta. Rivals attacking other players are ignored.

**Loot.** Drops that end in **(Celestial)** are picked up as they fall, by the last word of their name (*SSJ4 Gogeta's explosive red aura (Celestial)* → `get aura`). Everything else (Legendary drops, loot boxes, plain halos and tails) is left on the ground.

## Commands

| Command | Effect |
|---|---|
| `gog start [n]` | Count your materials, then loop (at most n rounds) |
| `gog check` | Count your Essences and Diamonds: how many rounds you can run |
| `gog stop` | Stop |
| `gog buy <n>` | Buy n Essences from a Dying Star from the event shop. It reads `eshop` first, because the item numbers change with each event, and never buys more than your event points cover. It counts the *You spend 500 epoints* replies and says if any purchase didn't go through |
| `gog attack <cmd>` | Attack sent as `<cmd> <target>`, on bosses and rivals (default `de`, death beam) |
| `gog status` | Phase, rounds done, and whether a rival is being fought |

Celestial Diamond Gemstones can't be bought: they drop from bosses.

## When it stops by itself

- You run out of Essences or Diamonds, or the round limit is reached.
- Kami doesn't take the items within 15 seconds of `say yes`.
- Goku and Vegeta don't land within 30 seconds, or a boss can't be reached after 5 tries.
- A fight goes 3 minutes without a kill, or a rival fight takes over 5 minutes.
