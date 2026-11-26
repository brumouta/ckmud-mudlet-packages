# Gumshoe for Mudlet and the CKMud client

`gumshoe.xml` is one copy of Gumshoe for both:

- **Mudlet:** install it with Package Manager → Install. Uninstall the old Gumshoe package first.
- **CKMud client:** put it in the plugin catalog (id `gumshoe`). Before installing, switch off or
  remove the old GumshoeCK package.

Both get the same game logic, commands and Repeat. The client also gets the Plugins dashboard card
and plugin control, which Mudlet has no equivalent for. In Mudlet, Repeat lasts until Mudlet
closes. In the client, the dashboard setting keeps it on across logins.

It is built from:

- `head.lua`: works out whether it is running in Mudlet or the client. In the client, it fills the
  sandbox gaps (`os.time`, `os.date`, `io.open`, `cecho` colours).
- `Gumshoe.mpackage` (built from `../src/Gumshoe.lua` with `python3 tools/build.py Gumshoe`): the game
  logic, unchanged.
- `tail.lua`:
  - **Both:** the every-line trigger and the `gum` alias (a regex alias in Mudlet, `mud.alias` in
    the client).
  - **Both:** Repeat, via `gum repeat on|off`. After each case, it opens the next one when Jaco has
    it, 20 minutes after the last one, then runs and accuses with Auto. `gum stop` ends it.
    Right after a case it goes back to Jaco on the Front Steps and waits there. `gum repeat wait
    <commands>` then sends your own commands from the Front Steps (`;` between them, aliases work
    in Mudlet), to wait somewhere else; `gum repeat wait jaco` goes back to just waiting at Jaco.
    The choice is saved in `gumshoe_repeat.lua` in the profile.
  - **Mudlet only:** other packages can step aside for a repeat case. Just before a case starts it
    raises the event `gumshoe.repeat.starting`; a package can call `gum.hold(name)` and later
    `gum.release(name)` to make it wait (for at most 3 minutes). Once it's back at Jaco after the
    case, or repeat is turned off, it raises `gumshoe.repeat.done`; a package that sets
    `gum.rep.claimed = name` carries on from there instead of the `gum repeat wait` commands.
    Autolearn uses this to pause its learning.
  - **Client only:** the dashboard card (settings, buttons, help, status) and plugin control.
    Gumshoe claims movement before it walks and gives it back when it stops.

Keep editing the game logic in `../src/Gumshoe.lua` and the additions in `tail.lua`, then rebuild.
Don't edit the built script inside Mudlet: the next build would overwrite those changes.

## Rebuild and test

1. Raise the version in `tail.lua` (and in `../package.json` if the game logic changed).
2. From the root of this repository, run the tests. `sh tests/run.sh` builds the package, then
   `dist/gumshoe.xml` (with `tools/plugin/build-plugin.cjs`, a copy of the CKMud-2D-Desktop build
   script), then runs `test.lua` against it in Lua 5.1. CI does the same, and the release attaches
   `gumshoe.xml` next to the `.mpackage` files. To build by hand:

   ```bash
   python3 tools/build.py Gumshoe
   node tools/plugin/build-plugin.cjs -o dist/gumshoe.xml packages/Gumshoe/Gumshoe-plugin/head.lua dist/Gumshoe.mpackage packages/Gumshoe/Gumshoe-plugin/tail.lua
   cd packages/Gumshoe/Gumshoe-plugin && lua5.1 test.lua ../../../dist/gumshoe.xml
   ```

   They run the built file in stand-ins for the client's sandbox and for Mudlet (51 checks), and
   send nothing to the game.
