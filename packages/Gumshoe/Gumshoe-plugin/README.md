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
  - **Client only:** the dashboard card (settings, buttons, help, status) and plugin control.
    Gumshoe claims movement before it walks and gives it back when it stops.

Keep editing the game logic in `../src/Gumshoe.lua` and the additions in `tail.lua`, then rebuild.
Don't edit the built script inside Mudlet: the next build would overwrite those changes.

## Rebuild and test

1. Raise the version in `tail.lua` (and in `../package.json` if the game logic changed).
2. From the root of this repository, build the package, then the plugin with the build script
   from the CKMud-2D-Desktop repository (`scripts/build-plugin.cjs`):

   ```bash
   python3 tools/build.py Gumshoe
   node <CKMud-2D-Desktop>/scripts/build-plugin.cjs -o dist/gumshoe.xml packages/Gumshoe/Gumshoe-plugin/head.lua dist/Gumshoe.mpackage packages/Gumshoe/Gumshoe-plugin/tail.lua
   ```

3. From this folder, run the tests:

   ```bash
   lua5.1 test.lua ../../../dist/gumshoe.xml
   ```

   They run the built file in stand-ins for the client's sandbox and for Mudlet (51 checks), and
   send nothing to the game.
