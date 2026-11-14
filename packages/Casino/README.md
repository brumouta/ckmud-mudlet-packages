# Casino — Lucky Monkey Casino bots and advisors

Command: `casino`

Every casino game in one package. Each game keeps its own command; `casino` lists them.

| Game | Command | What it does |
|---|---|---|
| Blackjack | `bj help` | Plays blackjack with basic strategy after you `cjoin` |
| Video Poker | `vp help` | Plays the Jacks or Better machine with the standard strategy |
| Slots | `slot help` | Pulls a slot machine with pull, stop loss, target and keep limits |
| High Stakes | `hs help` | Advice on your turn in the Friday hold'em tournament; `hs go` sends it |

## Casino commands

| Command | Effect |
|---|---|
| `casino` / `casino help` | List the games and their commands |
| `casino status` | Every game at a glance, plus the Lucky Tails and XP earned while a bot played |
| `casino stop` | Stop every bot |
| `casino reset` | Clear the casino-wide Lucky Tails and XP |

## Shared by every game

- **`cjoin`**: the package's `cjoin` alias sends `cjoin` and tells each table game you sat down. A game only arms itself if its dealer offered the seat, so joining another table doesn't start the blackjack bot.
- **Rewards**: `You earn N Lucky Tails` and `You have gained N <stat> XP` are counted for the game whose bot is playing, and in the casino-wide totals. Nothing is counted while no bot plays, because the same lines come from outside the casino too.
- **MSDP** (optional): your name comes from it when it's installed.

## Upgrading from the separate packages

Uninstall **Blackjack**, **VideoPoker** and **HighStakes** in the Package Manager first, then install **Casino**. Otherwise their triggers fire twice.

## Adding a game

Add `src/<Game>.lua` (after `Core.lua` in `package.json`'s `scripts`), a trigger folder and its alias, and register it at the end of the script:

```lua
casino.register{
  key = "cw", title = "Casino War", command = "cw",
  active = function() return CW.active end,   -- the bot is playing (rewards go to it)
  stop = CW.stop,                             -- casino stop
  join = CW.join,                             -- you typed cjoin
  luckyTails = CW.luckyTails, xp = CW.xp,     -- optional per-game reward counts
  status = function() return "12 rounds, net +5,000,000" end,
}
```

Use the core helpers instead of copying them: `casino.logger(tag)`, `casino.num`, `casino.fmt`, `casino.signed`, `casino.parseAmount`, `casino.me`.


## Blackjack

Command: `bj`

Plays blackjack at the casino table using basic strategy, and keeps session stats.

### Usage

1. Wait for `A Blackjack Dealer says, 'Use 'cjoin' to join the table.'`
2. Type `cjoin` yourself. The bot only arms when a seat was offered.
3. On `Welcome to the table, <you>!` the bot switches on and bets (`blackjack bet`) every round until you `bj stop`.

### Commands

| Command | Effect |
|---|---|
| `bj help` | List the commands |
| `bj status` | Bot state, last hand, rounds / won / lost, zenni net, Lucky Tails, intelligence XP, moves |
| `bj start` / `bj stop` | Turn the bot on or off while seated |
| `bj bet <command>` | Change the bet command (default `blackjack bet`) |
| `bj delay <secs>` | Pause before each action (default 1) |
| `bj reset` | Clear the stats |

### Strategy

Standard basic strategy, assuming the dealer stands on soft 17. It recognises soft hands (`[ A] [ 4]` is a soft 15), only doubles on the first two cards when the prompt offers `cdouble`, and reads the dealer's upcard from the table. It moves once per new card, because the game repeats the options prompt after every line, and moves again if the dealer nudges (`Well <you>, what would you like to do?`) more than 5 seconds after its last move.

Each double puts in a second bet, so with a 20,000,000 bet a doubled hand risks 40,000,000.


## Video Poker

Command: `vp`

Plays the casino's **Jacks or Better** video poker machine (`vpoker`) with the standard strategy, and keeps session stats.

### Usage

1. Go to the video poker machine.
2. Type `vp start`. The bot looks at the machine (`vpoker`). If a hand is already dealt it plays that one; otherwise it deals.
3. Each hand: `vpoker deal` → picks the cards to hold → `vpoker draw <positions>` → deals again.
4. `vp stop` finishes the hand on the table and stops. `vp stop now` stops right away.

### Commands

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

### Strategy

This machine pays **Full House 8, Flush 5** ("8/5" Jacks or Better). The bot uses the standard ranked list for 8/5, holding the first pattern that matches from the top: pat royal/straight flush/quads → 4 to a royal → pat full house/flush/straight → trips → 4 to a straight flush → two pair → high pair → 3 to a royal → 4 to a flush → 10-J-Q-K → low pair → 4 to an outside straight → … → one high card → discard everything.

**It still loses on average.** With perfect play, 8/5 Jacks or Better at five coins returns about **97.3%** of what you bet. At 25,000,000 zenni a hand, that's an expected loss of around 0.7m zenni per hand. The bot plays it as well as it can be played; the reasons to run it are the Lucky Tails and STR XP for two pair and better. Set a `vp stoploss`.

### How it reads the machine

- The five cards come from the `[3C] [JC] [QS] [10D] [KH]` line, and the hand is played when `Type 'vpoker hold <positions>'...` appears.
- The hand ends on the machine's result line (`Jacks or Better returns your 25,000,000 zenni.` / `No win. You lose your 25,000,000 zenni.`), or on the `Credit:` line if no result line shows up. The machine's result is what gets counted; if the bot's own reading of the cards disagrees, it says so.
- `vp status` shows the zenni paid in and out, and the true net from the `Credit:` line.
- If nothing answers for 10 seconds, it sends `vpoker` to see where things stand.


## Slots

Command: `slot`

Stand at a slot machine and `slot start`. It sends `pull <lines>`, waits for `You won ...` / `You lost your ...`, and pulls again a second later.

| Command | Effect |
|---|---|
| `slot start` / `slot stop` | Start pulling / finish the pull on the machine, then stop |
| `slot status` | Pulls, paying pulls, full lines, Dragonballs, best win, zenni in / out / net, % returned, Lucky Tails, STR XP |
| `slot lines <1-5>` | Lines per pull (default 5). Each line is another bet: 1 middle row, 2 + top, 3 + bottom, 4 + top-left diagonal, 5 + bottom-left diagonal |
| `slot pulls <n>` | Stop after n pulls (0 = no limit) |
| `slot stoploss <zenni>` / `slot target <zenni>` | Stop once down / up this much, e.g. `500m`, `2b` (0 = off) |
| `slot keep <zenni>` | Stop before your zenni drops below this (needs MSDP; 0 = off) |
| `slot delay <secs>` | Pause between a result and the next pull (default 1) |
| `slot quiet on\|off` | Hide the machine's 9 lines a pull and show one summary line instead (default on) |
| `slot reset` | Clear the stats |

Each pull is scored with the machine's payout rules (from `payout`): a full line pays the symbol's multiplier x the line bet x the lines played, the first two reels matching pay 10% of that, the middle row plus another row of the same symbol pays x10 and all three rows x25. The summary line names what paid (`Cherry diagonal`, `2x Z top`), a Dragonball line raises an alert, and if the machine ever pays something different from the score you get a warning with the reels.

If the machine doesn't answer a pull in 8 seconds it pulls again; after two unanswered retries it stops (not at a machine, or out of zenni).

Slots have no strategy, and the house wins on average. Lucky Tails (full lines only) and STR XP only come from **[VIP]** machines.

## High Stakes

Command: `hs`

Advice for the Friday **High Stakes** no limit hold'em tournament. On your turn it shows your hand, your chance to win against the players still in, the pot odds, and a tight-aggressive suggestion. `hs go` sends the suggestion when you agree with it. If the dealer warns "ten seconds" and you haven't moved, it plays the suggestion for you so the turn isn't lost (`hs auto off` turns that off).

```
[hs] KS AC  on  AD 10H 9H 6S AH
     Win 81% vs 2 | 75M to call, pot 1.6B: need 4%
     RAISE  Three of a Kind: well ahead, raise   (hs go: craise)
```

With ten seconds left, the dealer's warning repeats the advice in red and plays it (unless `hs auto off`).

Tip: bind a key to `hs go` (Toolbox → Keys) so playing the suggestion is one keystroke.

### Commands

| Command | Effect |
|---|---|
| `hs` | Show this turn's advice again |
| `hs auto on\|off` | Play the suggestion by itself at the dealer's ten seconds warning (default on) |
| `hs go` | Send the suggested move (`ccall`, `craise 450m`, `cbet all`, `cfold`...) |
| `hs on` / `hs off` | Show advice on your turns (default on) |
| `hs sims <n>` | Simulated deals per decision (default 3000) |
| `hs players` | How often each player went all in, and their last shown hands |
| `hs status` | Hands seen, pots won, and where you finished |
| `hs reset` | Clear stats and player notes |

### How it decides

**Before the flop**, it uses starting hand tiers:
- premium: AA–JJ, AK
- strong: TT, 99, AQ, AJs, KQs
- good: 88, 77, ATs, AJo, KJs, KQo, QJs, JTs
- playable: small pairs, suited aces, KTs, QTs, T9s, 98s, KJo, ATo, QJo

Then:
- **Nobody has raised yet:** raise to 3 big blinds with good hands or better. From the small blind, complete for half a bet with a playable hand, any suited hand, any ace or king, or connected cards (8-7, 9-7...). Fold the rest.
- **Facing a raise:** re-raise premium hands to 3×. Call with strong or good hands if it costs at most 10% of your stack. Otherwise fold.
- **Facing an all in, or a bet over a third of your stack:** assume they hold a top-25% hand. Call only when your chance against that range beats the pot odds, or with a premium hand. With a premium hand it moves all in if it can.
- **Your stack is 10 big blinds or less:** all in with any tier hand or any ace, otherwise fold.

**After the flop**, it works out your chance to win by dealing out a few thousand random finishes against the players still in. Each player only gets hands that fit what they've done:
- **Their starting hand** narrows with the size of their bet: 70% of hands when nobody bet, 60% for a small bet, 40% for half the pot, and the top 25% for a pot-sized bet or an all in.
- **What they must have on this board** depends on how often they've bet or raised since the flop. Once: at least a pair or a draw (calling a bet counts the same). Twice: top pair or better. Three times or more: two pair or better. A player who bets every street and keeps re-raising almost never has just one pair.

Then:
- **Checked to you:** bet two-thirds of the pot when you're comfortably ahead, otherwise check.
- **Facing a bet:** raise when well ahead, call when your chance beats the pot odds (with a 3-point margin), otherwise fold.
- **They keep raising** (three bets or raises from one player): only two pair or better raises back. One pair calls if the odds are there, otherwise folds. That's the min-raise war that cost a whole stack with top pair (hand 19 of the November 7 log).
- **Your hand is named for what your cards add**: 66 on a Q-Q board shows as `Two Pair (mostly the board: a weak pair)`, and a river where the board plays shows `(mostly the board: nothing)`.
- Any raise bigger than half your stack becomes `craise all`.

During the **early limits** (hands 1–10) the amounts are fixed, so it sends a plain `craise`, or `cbet` with the offered amount.

### Limits

- It plays the odds against typical ranges, not against these particular players. Cicada shoving any two cards is exactly where your own judgement beats it, and `hs players` shows their all-in history to help.
- It needs to see your cards. If you load it mid-hand, type `ctable`.
- It reads the tournament start, the dealer's "out of time" moves (so `hs go` doesn't send a stale move), main and side pots, and your knockout place (`hs status`).
- Check CKMud's rules on scripts at player tables. This package only advises; every move is sent by you.
