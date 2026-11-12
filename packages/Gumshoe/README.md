# Gumshoe — Briefs mansion cases

Command: `gum`

Solves Jaco's party cases at the Briefs house (`help mansion`). Type `gum case` to go to Jaco and open a Hard case, step inside and type `gum run`. It does the legwork, then tells you who did it. You make the arrest yourself.

## Commands

| Command | Effect |
|---|---|
| `gum case [easy\|normal\|hard]` | Go to Jaco on the Front Steps and `say case` (Hard unless you say otherwise). From inside the house it walks out. Anywhere else it uses the return capsule (`use mansion`, to the Briefs Family Garden, then 6 west). With no capsule it uses `focus 'instant' bulma` (Bulma's Workshop), then `pursue jaco`. A failed instant (*You failed.*) is tried up to 3 times, then it pursues Jaco from wherever you are |
| `gum run` | Do the whole case: search, question, inspect, door log, sealed rooms, confront, then solve |
| `gum question` | Only question everyone not questioned yet: walks to where it last saw each guest (looking in unseen rooms for the rest), then solves |
| `gum stop` | Stop walking. Everything found so far is kept |
| `gum solve` | Re-read the notebook, the four statement tables and `accuse`, then show the evidence, each suspect's alibi and the accusation it points to |
| `gum accuse` | Send the suggested accusation. You still type `accuse yes` |
| `gum status` | What's left: rooms to search, guests to question, sealed rooms, secrets |
| `gum go <room>` | Walk to a room, e.g. `gum go kitchen` or `gum go lab` |
| `gum reset` | Forget the case (a new case resets by itself) |

## What `gum run` does

It walks to the nearest room with something left to do, does it, and repeats:

- **Search** every room the notebook lists until the game says *This room is done for now*. It searches again after every find, and waits whenever the game says *You are still turning this room over*.
- **Question** every guest, witnesses included, in whatever room it last saw them. Each answer goes straight into the alibis.
- **Inspect** where the case says: `inspect remains` at the scene of a murder (the time window and the two possible weapons), `inspect cradle` in the Study for a theft (when the loot was taken).
- **Read Garter's door log** for all four chimes in the Inner Hall.
- **Open the sealed rooms:**
  - The lab: `study portraits`, work the code out from the plaque (left to right, right to left, alphabetical, oldest to youngest or youngest to oldest), `press` it in the Lab Vestibule, then go down.
  - Bulma's Suite: `say` the phrase written on the back of a secret, on the Upper Landing East. (The game now also records the phrase in `notebook` once found; Gumshoe still takes it from the secret.)
  - The Gravity Chamber: `shut gravity` in the Robot Charging Bay. The lights go out, so it fetches the flashlight from the Hangar first, then searches the chamber.
- **Pitch dark?** If a search ever says *It is pitch dark*, it stops, fetches the flashlight from the Hangar (or, if that fails twice and the Gravity Chamber is already searched, does `reset breaker` in the Robot Charging Bay, which re-seals the chamber) and comes back to search that room again.
- **Confront** every secret, once every room has been searched.
- **Re-read** `notebook 9` to `notebook 12` (confessions change stories), `notebook guests` and `accuse`, then solve.
- If the cake clues disagree, it **plates** the top suspect in the Kitchen. If one clue is the only thing against the top suspect, it **analyzes** that clue in the Underground Lab. Then it solves again.

## The Phantom's calling cards

Sometimes a search turns up one of the Phantom's black calling cards. It isn't a finding and has nothing to do with the case, but you keep it if you solve the case in time, and three of them summon a secret boss. Gumshoe:

- says when it finds one (there's nothing to pick up: finding it is enough), and `gum status` and the solve report remind you there's one on this case;
- counts it when the case closes solved (not when it goes cold) and says once you have three or more (then `say gallery` to Jaco brings the Phantom to his Gallery, south of the Front Steps);
- reads the count from `casebook` (*Calling cards: 1*), so type `casebook` once after installing to start from your real count.

Cards turn up in 1 case in 8 on Easy, 1 in 4 on Normal and 1 in 2 on Hard. The Kitchen cabinet also sells `buy cardguarantee` (6 vouchers), which hides a card in your next case. You still have to find it and solve the case.

## How it decides

- **Witnesses** (from `notebook guests`) never lie, and nor does the seating chart, which is who sat in the Dining Room.
- **Alibis.** For each suspect, at each hour the attack could have happened:

  | Result | Meaning |
  |---|---|
  | **seen** | A witness or the chart puts them there |
  | **LIED** | A witness was in that room and doesn't name them, the chart leaves them out of the Dining Room, or the door log counts fewer heads than claim the room (when the extra ones are exactly those nobody else there names, only they lied) |
  | **unbacked** | They say they were with people in that room who name each other but not them (Roshi "confessing" to the Robot Workshop with Yamcha and Pilaf, who only name each other) |
  | **fits** | Only suspects back the story, but the door log count matches |
  | **alone** | Only suspects back the story, and no log count can check it (sensor broken) |

  A confession is checked the same way. A confession nobody backs, after a first story a witness or the chart already disproved, counts as **LIED**: they lied twice. In the first case it was mapped from, Yamcha "confessed" to being in the Family Lounge at midnight, but Krillin and Dende were there and never named him.
- **Evidence** is matched against the guest table by keyword: footprints for tread, a hair for hair colour, scorch marks or still air for ki, frosting or an untouched slice for the cake. When two clues disagree, one of them is planted, so neither counts until `analyze` or `plate` settles it. The alibi comes first (*find the one nobody saw*); a clue that doesn't fit only costs points, because a clue can be planted. When one doesn't fit the top suspect, it suggests analyzing that clue.
- **The time** is the window from the remains or the cradle, minus any hour the notebook or the party log rules out (*the radar was still in its cradle at nine*, *Dr. Briefs had found the cradle empty by midnight*, *by eleven, the alarm had already gone up*).
- **Murder:** the weapon is the one the notebook names. Until it does, it's whichever of the two was kept where the suspect had been before the attack, marked as a guess.
- **Accomplices:** one guest did it and another covered: the two swore they were together and each named the other. When the coverer is confronted they own up (*I was never in the Dining Room with Emperor Pilaf… I covered for them*), which names both. Before that, the partner is the suspect whose first story at that hour put them in the culprit's room, naming each other. The accusation is `accuse <culprit> and <partner> with <weapon> at <time>`.
- **Delayed sabotage:** the weapon was rigged earlier and went off later. Jaco wants when it was *rigged*. The window from the remains, minus any hour the party log says *nothing had gone off yet*, gives when it went off; the delay timer in the scene room (*set two chimes before it fired*) counts back to the rigging hour. The rigger stood at the scene then, so their story for that hour is the lie to find. The weapon's empty case (somewhere in the house) or the notebook names the weapon and the room it was kept in; whoever claimed that room earlier in the night scores higher. The accusation is `accuse <suspect> with <weapon> rigged at <time>`.
- **Theft:** three Hoi Poi capsules are hidden in party rooms. The stash is the capsule room the thief says they went to *after* the theft; the two decoys are in rooms they never went to afterwards. A suspect who went to exactly one capsule room afterwards scores higher. The accusation is `accuse <suspect> stash <room> at <time>`.
- Until guests are questioned there are no alibis: `gum solve` says so and never calls it solved.

## Limits

- **Case types:** murder, theft, accomplices and delayed sabotage are solved. For locked room (`accuse <suspect> through <room> at <time>`, not seen by anyone yet), `gum solve` still shows the alibis and evidence, but `gum accuse` won't send anything until a real case shows how the way in is found.
- **The map** is fixed, mapped from one case. If the house ever changes, the room list in `G.EXITS` needs updating.
- **Hard cases** are read from the intro: the lab analyzer is off, so it never suggests or walks to `analyze`. The extra liar and second broken log sensor need nothing special, but only the intro of a Hard case has been seen so far.
- **Monthly twists** (from `help mansion`): January a fast watch, February guest dolls, March a lying witness, April eggs, May Goten and Trunks run off with clues (tag them), June a storm, July a pair slips off, August dark rooms, September the moon roof, October masks, November a feast, December presents to unwrap. Only November's (the seating chart) has been seen; the others may need changes when they come.
- **Upgrading mid-case** keeps what the case has found so far and adds anything the new version needs, so you can install a fix without starting over.
