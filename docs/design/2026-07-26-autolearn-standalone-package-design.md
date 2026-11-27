> **History.** This is the original extraction design. Since Autolearn 4.0 the package no longer
> uses muddler, the vendored CK framework or the Node (fengari) simulation: it's built from
> `package.json` by `tools/build.py` and tested with plain Lua in `tests/`. See the package's README.

# Autolearn Standalone Package — Design

Date: 2026-07-26

> **Revision (same day):** the user asked for full independence from CK
> ("extract everything you need to make it work without the base package"),
> overriding the sub-package recommendation below. The package is now
> `Autolearn` (not `CK-Autolearn`): it vendors the required core subsystems
> (init/table/feature/constant machinery, MSDP handlers, prompt lifecycle,
> skill scraping, score name/race parsing, state machine, modes, attack DB +
> cost model, send queue) and runs under its own `AL` global prefix, its own
> `Autolearn` settings database, and its own `AL.*` events so it cannot corrupt
> an installed CK package. User-facing config commands are `AL features`,
> `AL constant <name>=<value>`, `AL update`; the bot command stays `autolearn`.
> Dropped as unnecessary for autolearn: zetabot/training/kaioken bots, buffs,
> combos, damage/affects tracking, tells, daily rewards, beep, fishing, and the
> cosmetic prompt rewriting (health % injection). Sections below describe the
> original sub-package design for context.

## Goal

Extract the autolearn feature (the Learning bot) out of the core CK package into its
own installable Mudlet package, so it can be versioned, installed, and updated
independently.

## Approaches considered

1. **Fully independent package (no CK required).** Rejected: the Learning bot depends
   on CK's MSDP feed, prompt parsing, skill scraping, state machine, mode system,
   attack database, and fight cost model (~2,500 lines). Vendoring these would fork the
   core, and both copies would fight over the same `CK` globals, named event handlers,
   and named timers when installed side by side.
2. **CK sub-package (chosen).** CK already ships a plugin system for exactly this:
   `CK-Chat`, `CK-Map`, and `CK-Hud` live in sibling repos, are installed with
   `CK pkg install <name>` from
   `https://github.com/CKMud-Mudlet-Scripts/<Short>/releases/latest/download/CK-<Short>.mpackage`,
   and register themselves with `require("CK"):register(name, version)`. Autolearn
   becomes `CK-Autolearn`, repo shortname `Autolearn`.
3. **Keep code in CK behind a feature flag.** Rejected: doesn't satisfy "standalone
   package" — no independent install/update.

## What moves into the new package

| Item | From (CK) | To (CK-Autolearn) |
| --- | --- | --- |
| Learning bot script | `src/scripts/Bots/Learning.lua` | `src/scripts/Learning.lua` |
| `autolearn` alias ("learning") | `src/aliases/aliases.json` | `src/aliases/aliases.json` |
| `autolearn no target` trigger | `src/triggers/triggers.json` | `src/triggers/triggers.json` |

The feature flag `learning.use_zeta` and constants `learning.return_to_target` /
`learning.recall_isolation` are defined inside `Learning.lua` and move with it. They
keep their names, so existing persisted values in the shared CKMud DB carry over.

## What stays in CK

- Skill scraping triggers (`Learn Scrape`, `Learned Skill`, `Mastered Skill`) and
  `API.Skills` — used by `strike`/`blast`, ZetaBot, and auto-fight, not just autolearn.
- `Mode.Learning` enum entry and `Toggles.learning` — the mode system is core
  infrastructure referenced by the prompt renderer and `State:check`.
- MSDP handlers, prompt events, state machine, Fight/Attacks/Racials.

## New package layout (muddler project at repo root: `Autolearn/`)

```
Autolearn/
  mfile                        package "CK-Autolearn", version 26.07.26
  README.md                    install + usage + constants docs
  .github/workflows/main.yml   CI for when the dir moves to its own repo
  src/
    scripts/scripts.json       registration (guarded require("CK")) + Learning
    scripts/Learning.lua       local ck = require("CK")
    aliases/aliases.json       autolearn alias
    triggers/triggers.json     autolearn no target trigger
    resources/shenron.png      package icon
```

Key mechanical changes inside `Learning.lua`:
- `require("__PKGNAME__")` → `require("CK")` (the core module; `__PKGNAME__` would
  resolve to `CK-Autolearn`).
- Named timer/handler *owner* stays `__PKGNAME__` so Mudlet attributes them to the
  addon and cleans them up on uninstall.
- The registration entry in `scripts.json` pcall-guards `require("CK")` and prints an
  install hint if CK is missing.

## CK-side changes

- Delete `src/scripts/Bots/Learning.lua`; drop its entry from `Bots/scripts.json`.
- Remove the `learning` alias and `autolearn no target` trigger.
- Add `"Autolearn"` to the submodules list in `CK_pkg.lua` so
  `CK pkg install autolearn` works.
- Help/README: point `autolearn` at the new package.
- CI: build both packages from this repo (`workingDir` input of
  demonnic/build-with-muddler) until `Autolearn/` is moved to its own repo.

## Compatibility notes

- `CK pkg update all` picks the addon up automatically once registered.
- Uninstalling the addon leaves orphaned `learning.*` rows in the DB until CK's
  exit-time compaction removes them — same behavior as any removed feature.
- No load-order hazard: `require("CK")` loads `<profile>/CK/init.lua` directly from
  disk regardless of Mudlet package load order, and all cross-package calls
  (`CK.API.Learning:toggle`, trigger enable/disable) happen at user-command time.

## Testing

The repo has no test infrastructure (Mudlet-runtime Lua). Verification is:
1. `muddler` build of both projects must succeed (run locally in CI-equivalent form).
2. Lua syntax check of all changed/added `.lua` files.
3. Grep audit: no remaining `CK.API.Learning` / `autolearn` references in core CK
   except the help text pointing at the package.
