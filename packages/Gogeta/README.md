# Gogeta — Kami's timeline portal, on a loop

Command: `gog`

## Before it starts

`gog start` first runs `inventory` and `materials` and counts your **Essences from a Dying Star** and **Celestial Diamond Gemstones**. Each round uses one of each, so it runs as many rounds as the smaller count allows (or fewer, with `gog start <n>`). With none of either it doesn't start. Each finished round shows what's left, and it stops by itself when you run out. `gog check` only counts.

## Each round

1. `pursue kami`, then `say yes`. Kami takes one Essence and one Diamond and opens the portal.
2. When SSJ4 Vegeta says *What a waste of my time*, both have landed somewhere on Earth: `pursue goku`, then `de goku`.
3. When one of them dies, it attacks the other (`de vegeta` or `de goku`).
4. When they fuse (*standing before you is SSJ Gogeta*), he's right there: `de gogeta` until SSJ4 Gogeta dies.
5. Back to Kami.

Getting to the bosses:

- **Far away: pursue.** Goku and Vegeta after they land, and any boss after a rival fight, are reached with `pursue`.
- **Seen moving: sense.** If Goku, Vegeta or Gogeta *leaves* or *flies* somewhere, they're nearby, so it uses `sense` and keeps attacking. If *You lose your concentration*, it senses again (up to 5 tries). If *You can't seem to sense … from here*, it falls back to `pursue`.

**Super Saiyan 3 Goku.** When he's around, `pursue goku` finds him instead of SSJ4 Goku. He dies in one hit, then it pursues Goku again.

**Ultra Instinct.** While the loop runs, it keeps Ultra Instinct up: when the prompt loses `[UI]` (*Lacking God Ki, you lose your heightened ultra state*), it casts `focus 'ultra instinct'` again as soon as god ki is back to 5% (`lua gog.uiMinGk = 10` to change). `gog ui tui` keeps True Ultra Instinct up instead (`focus 'ultra instinct'` then `focus 'true ultra instinct'`), `gog ui off` leaves it to you.

**Emergency heal.** `lua gog.panicCmd = "sz"` runs that command (through your aliases) when your powerlevel drops to 35% during the loop, at most every 30 seconds. Off by default.

**Rivals.** When a rival crashes down on you (*The sky splits open as … crashes down upon you* or *… flies out of nowhere and attacks you*), the round pauses. Rivals attacking other players are ignored. While a rival is alive:

- it attacks the rival again every 15 seconds, because strong ones (a nemesis) take a while;
- if the attack finds nobody (*Death Beam who?*), the rival moved, so it senses it;
- once every rival is dead, it waits until your powerlevel is back to 80% (at most 2 minutes, read from the prompt), then picks up where the round was: back to Kami, back to Goku and Vegeta, or after Gogeta;
- if no rival dies within 10 minutes (it fled), it forgets them and carries on. `gog resume` does that by hand.

If you die (*You are dead!*), it stops.

**Loot.** Drops that end in **(Celestial)** are picked up as they fall, by the last word of their name (*SSJ4 Gogeta's explosive red aura (Celestial)* → `get aura`). Everything else (Legendary drops, loot boxes, plain halos and tails) is left on the ground.

## Commands

| Command | Effect |
|---|---|
| `gog start [n]` | Count your materials, then loop (at most n rounds) |
| `gog check` | Count your Essences and Diamonds: how many rounds you can run |
| `gog stop` | Stop |
| `gog resume` | Forget the rivals being fought and carry on with the round |
| `gog buy <n>` | Buy n Essences from a Dying Star from the event shop. It reads `eshop` first, because the item numbers change with each event, and never buys more than your event points cover. It counts the *You spend 500 epoints* replies and says if any purchase didn't go through |
| `gog ui <ui\|tui\|off>` | Keep Ultra Instinct (or True Ultra Instinct) up while looping, or not (default `ui`) |
| `gog attack <cmd>` | Attack sent as `<cmd> <target>`, on bosses and rivals (default `de`, death beam) |
| `gog status` | Phase, rounds done, and whether a rival is being fought |

Celestial Diamond Gemstones can't be bought: they drop from bosses.

## When it stops by itself

- You run out of Essences or Diamonds, or the round limit is reached.
- Kami doesn't take the items within 15 seconds of `say yes`.
- Goku and Vegeta don't land within 30 seconds, or a boss can't be reached after 5 tries.
- A boss fight goes 3 minutes without a kill.
- You die.
