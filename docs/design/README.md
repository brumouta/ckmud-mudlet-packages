# Design notes

How Autolearn, KaiokenTrain and Chores were extracted from the [CK package](https://github.com/CKMud-Mudlet-Scripts/CK) into standalone packages. Each note was written before its extraction and is kept as it was, as a record of the decisions.

They were written while the packages still lived inside the CK repository. Read their paths with that in mind:

- `Autolearn/`, `Chores/`, `KaiokenTrain/` at "the repo root" are now `packages/<Package>/` here.
- `src/scripts/Bots/Learning.lua`, `src/scripts/Bots/Kaioken.lua` and the other `src/...` paths that are being removed refer to the CK package.
- Where they plan to move a package "to its own repo", they all ended up together in this repository instead.
- The muddler projects, the vendored CK framework and the Node (fengari) simulations they describe are gone: since Autolearn 4.0, KaiokenTrain 3.0 and Chores 3.0 each is built from `package.json` by `tools/build.py` and tested with plain Lua in `tests/`.

| Note | Package |
|---|---|
| [2026-07-26 Autolearn](2026-07-26-autolearn-standalone-package-design.md) | [Autolearn](../../packages/Autolearn) |
| [2026-07-26 KaiokenTrain](2026-07-26-kaioken-standalone-package-design.md) | [KaiokenTrain](../../packages/KaiokenTrain) |
| [2026-07-27 Chores](2026-07-27-chores-standalone-package-design.md) | [Chores](../../packages/Chores) |
