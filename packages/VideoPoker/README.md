# VideoPoker — video poker bot

Command: `vp`

Plays the casino's **Jacks or Better** video poker machine (`vpoker`) with the standard strategy, and keeps session stats.

## Usage

1. Go to the video poker machine.
2. Type `vp start`. The bot looks at the machine (`vpoker`). If a hand is already dealt it plays that one; otherwise it deals.
3. Each hand: `vpoker deal` → picks the cards to hold → `vpoker draw <positions>` → deals again.
4. `vp stop` finishes the hand on the table and stops. `vp stop now` stops right away.

## Commands

| Command | Effect |
|---|---|
| `vp start` / `vp stop` | Start, or finish the current hand and stop |
| `vp stop now` | Stop right away (a dealt hand stays on the machine) |
| `vp status` | Hands, each result, coins bet and won, % returned, zenni net, Lucky Tails, STR XP |
| `vp advise` | Shows what the strategy would hold for the cards on screen, without playing |
| `vp coins <1-5>` | Coins a hand (default 5, the only bet that pays the 4,000 coin royal) |
| `vp hands <n>` | Stop after n hands (0 = no limit) |
| `vp stoploss <zenni>` | Stop once down this much, e.g. `500m`, `2b` (0 = off) |
| `vp target <zenni>` | Stop once up this much (0 = off) |
| `vp delay <secs>` | Pause before each command (default 1) |
| `vp quiet on\|off` | Hide the paytable while the bot plays (default on) |
| `vp reset` | Clear the stats |

It also stops when your credit can't cover another hand, or when the machine doesn't answer three looks in a row (e.g. you walked away).

## Strategy

This machine pays **Full House 8, Flush 5** ("8/5" Jacks or Better). The bot uses the standard ranked list for 8/5, holding the first pattern that matches from the top: pat royal/straight flush/quads → 4 to a royal → pat full house/flush/straight → trips → 4 to a straight flush → two pair → high pair → 3 to a royal → 4 to a flush → 10-J-Q-K → low pair → 4 to an outside straight → … → one high card → discard everything.

**It still loses on average.** With perfect play, 8/5 Jacks or Better at five coins returns about **97.3%** of what you bet. At 25,000,000 zenni a hand, that's an expected loss of around 0.7m zenni per hand. The bot plays it as well as it can be played; the reasons to run it are the Lucky Tails and STR XP for two pair and better. Set a `vp stoploss`.

## How it reads the machine

- The five cards come from the `[3C] [JC] [QS] [10D] [KH]` line, and the hand is played when `Type 'vpoker hold <positions>'...` appears.
- The hand ends on the machine's result line (`Jacks or Better returns your 25,000,000 zenni.` / `No win. You lose your 25,000,000 zenni.`), or on the `Credit:` line if no result line shows up. The machine's result is what gets counted; if the bot's own reading of the cards disagrees, it says so.
- `vp status` shows the zenni paid in and out, and the true net from the `Credit:` line.
- If nothing answers for 10 seconds, it sends `vpoker` to see where things stand.
