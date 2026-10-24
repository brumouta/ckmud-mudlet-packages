# HighStakes — High Stakes tournament advisor

Command: `hs`

Advice for the Friday **High Stakes** no limit hold'em tournament. On your turn it shows your hand, your chance to win against the players still in, the pot odds, and a tight-aggressive suggestion. **It never acts by itself**: `hs go` sends the suggestion when you agree with it.

```
[hs] KS AC  on  AD 10H 9H 6S AH
     Win 81% vs 2 | 75M to call, pot 1.6B: need 4%
     RAISE  Three of a Kind: well ahead, raise   (hs go: craise)
```

With ten seconds left, the dealer's warning repeats the advice in red.

Tip: bind a key to `hs go` (Toolbox → Keys) so playing the suggestion is one keystroke.

## Commands

| Command | Effect |
|---|---|
| `hs` | Show this turn's advice again |
| `hs go` | Send the suggested move (`ccall`, `craise 450m`, `cbet all`, `cfold`...) |
| `hs on` / `hs off` | Show advice on your turns (default on) |
| `hs sims <n>` | Simulated deals per decision (default 3000) |
| `hs players` | How often each player went all in, and their last shown hands |
| `hs status` | Hands seen and pots won |
| `hs reset` | Clear stats and player notes |

## How it decides

**Before the flop**, it uses starting hand tiers:
- premium: AA–JJ, AK
- strong: TT, 99, AQ, AJs, KQs
- good: 88, 77, ATs, AJo, KJs, KQo, QJs, JTs
- playable: small pairs, suited aces, KTs, QTs, T9s, 98s, KJo, ATo, QJo

Then:
- **Nobody has raised yet:** raise to 3 big blinds with good hands or better. Fold the rest, or complete the small blind with a playable hand.
- **Facing a raise:** re-raise premium hands to 3×. Call with strong or good hands if it costs at most 10% of your stack. Otherwise fold.
- **Facing an all in, or a bet over a third of your stack:** assume they hold a top-25% hand. Call only when your chance against that range beats the pot odds, or with a premium hand. With a premium hand it moves all in if it can.
- **Your stack is 10 big blinds or less:** all in with any tier hand or any ace, otherwise fold.

**After the flop**, it works out your chance to win by dealing out a few thousand random finishes against the players still in. Their likely hands narrow with the size of their bet: 70% of hands when nobody bet, 60% for a small bet, 40% for half the pot, and the top 25% for a pot-sized bet or an all in.
- **Checked to you:** bet two-thirds of the pot when you're comfortably ahead, otherwise check.
- **Facing a bet:** raise when well ahead, call when your chance beats the pot odds (with a 3-point margin), otherwise fold.
- Any raise bigger than half your stack becomes `craise all`.

During the **early limits** (hands 1–10) the amounts are fixed, so it sends a plain `craise`, or `cbet` with the offered amount.

## Limits

- It plays the odds against typical ranges, not against these particular players. Cicada shoving any two cards is exactly where your own judgement beats it, and `hs players` shows their all-in history to help.
- It needs to see your cards. If you load it mid-hand, type `ctable`.
- Check CKMud's rules on scripts at player tables. This package only advises; every move is sent by you.
