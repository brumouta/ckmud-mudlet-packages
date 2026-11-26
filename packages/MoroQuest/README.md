# MoroQuest

Helpers for the Moro questline (Agent Merus, Galactic Patrol). Type `moro help`.

| Command | What it does |
|---|---|
| (automatic) | When Merus hands you the prisoner manifest it sends `look prisonmanifest`, then shows the five real names; click one to send `decipher <name>` |
| `moro decipher` | Send `decipher` for each name |
| `moro auto [on\|off]` | Send them as soon as the manifest is read (default off) |
| `moro decode a d <words>` | Decode words by hand with any key |
| `moro bulletins [planet]` | Post the wanted bulletins at every spaceport still to do (or just one planet) |
| `moro comms` | Go to the Station's comms deck for the recorded transmission (runs by itself after the last bulletin) |
| `moro attack <cmd>` | Attack used on rivals that jump you on the way (default `de`) |
| `moro stop` | Stop the bulletin or comms run |

## The manifest

The broken seal gives a letter shift ("A reads as D" means every letter was moved 3 forward), so
moving each letter back gives the names: Ydqwd, Eudnnd, Ulphedfn, Whnwhn, Vdjdqer are Vanta,
Brakka, Rimeback, Tektek, Saganbo. Any key works, and so does a manifest the game wraps.

## The bulletins

Every leg starts with `recall` and `press button` (the Zeno Button to the Grand Atrium), walks to
the planet's vortex and goes through, then on to the spaceport and `post bulletin`:

| Planet | From the Grand Atrium | To the spaceport |
|---|---|---|
| Earth | `s s enter vortex` | `pursue bartender`, `w`, `s` (Landing Pad) |
| Vegeta | `s e e enter vortex` | `pursue pod master` (Zenkonia Spaceport) |
| Namek | `s w w enter vortex` | fly to Guru's Compound (`survey`), `enter`, `pursue guide` |
| Iceria | `n w w enter vortex` | fly to City of Zero Nexus (`survey`), `enter`, `n n n w` |
| Konats | `n e e enter vortex` | `pursue porter`, `s` (Landing Pad) |

The survey number is read from the `survey` list, not fixed. After each post it reads "Still to
post:" and goes on with what's left, so it can be stopped and started again. A rival that flies
out of nowhere gets `moro attack` (first word of their name); once they're dead the step is done
again (the pursue, or the flight).

## The recorded transmission

After the fifth bulletin it heads to the Station's comms deck: `recall` (Galactic Federation
HeadQuarters), `leave`, fly to the Galactic Patrol Station (number read from `survey`), `enter`,
then `n n w` to the Communications Deck, where Jaco's recording plays. It shows the landmark it
gives for the Prison Planet (landmark 12 on the Space Map survey).
