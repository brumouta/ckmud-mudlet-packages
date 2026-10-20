# Blackjack — blackjack table bot

Command: `bj`

Plays blackjack at the casino table using basic strategy, and keeps session stats.

## Usage

1. Wait for `A Blackjack Dealer says, 'Use 'cjoin' to join the table.'`
2. Type `cjoin` yourself. The bot only arms when a seat was offered.
3. On `Welcome to the table, <you>!` the bot switches on and bets (`blackjack bet`) every round until you `bj stop`.

## Commands

| Command | Effect |
|---|---|
| `bj help` | List the commands |
| `bj status` | Bot state, last hand, rounds / won / lost, zenni net, Lucky Tails, intelligence XP, moves |
| `bj start` / `bj stop` | Turn the bot on or off while seated |
| `bj bet <command>` | Change the bet command (default `blackjack bet`) |
| `bj delay <secs>` | Pause before each action (default 1) |
| `bj reset` | Clear the stats |

## Strategy

Standard basic strategy, assuming the dealer stands on soft 17. It recognises soft hands (`[ A] [ 4]` is a soft 15), only doubles on the first two cards when the prompt offers `cdouble`, and reads the dealer's upcard from the table. It moves once per new card, because the game repeats the options prompt after every line, and moves again if the dealer nudges (`Well <you>, what would you like to do?`) more than 5 seconds after its last move.

Each double puts in a second bet, so with a 20,000,000 bet a doubled hand risks 40,000,000.
