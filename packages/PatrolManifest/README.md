# PatrolManifest

Merus's scrambled prisoner manifest. The broken seal gives a letter shift ("A reads as D" means
every letter was moved 3 forward), and the five priority names are written with it. This package
reads the key and the names and gives you the real ones.

| Command | What it does |
|---|---|
| (automatic) | When Merus hands you the manifest it sends `look prisonmanifest`, then shows the five names; click one to send `decipher <name>` |
| `pm go` | Send `decipher` for each name |
| `pm auto [on\|off]` | Send them as soon as the manifest is read (default off) |
| `pm decode a d <words>` | Decode by hand with any key |

Example: key A reads as D, names Ydqwd, Eudnnd, Ulphedfn, Whnwhn, Vdjdqer are
Vanta, Brakka, Rimeback, Tektek, Saganbo.
