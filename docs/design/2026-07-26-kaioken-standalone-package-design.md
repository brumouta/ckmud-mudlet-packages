# Kaioken Train Standalone Package — Design

Date: 2026-07-26

Mirror of the Autolearn extraction (see
`2026-07-26-autolearn-standalone-package-design.md`, revision note): pull the
`kaioken train` bot out of CK into a fully standalone Mudlet package.

## Shape

- Package `KaiokenTrain` (muddler project at repo root `KaiokenTrain/`),
  global prefix `KT`, own `KaiokenTrain` settings DB, own `KT.*` events —
  identical isolation strategy to Autolearn, so CK / Autolearn / KaiokenTrain
  can coexist without corrupting each other.
- The trainer's dependency set is small: state machine, mode system (trimmed
  to Kaioken/Interactive), `is_connected`/`is_rested`/Times core, MSDP
  handlers (fatigue, thirst, godki, staleness/reconnect), prompt lifecycle,
  and two parsers — `[Kaioken: X/Y]` from the prompt and
  "You have mastered kaioken xN." from `status` output (top-level trigger
  here; in CK it was a child of the status-gagging group, which is not
  vendored).
- User commands: `kaioken train` (unchanged), `KT` help, `KT features`,
  `KT constants`, `KT update`.
- Known CK bug fixed in the vendored copy: `Mode:switch` wrote
  `_mode.String` (capital S) for Kaioken so `Mode:toString()` reported the
  wrong mode; the standalone uses `_mode.string`.
- Behavior notes: `enter()` no longer sets `Toggles.hide_status` (the status
  gagging stays in CK), so enabling the trainer shows one `status` output
  when max kaioken is unknown. Because each bot package owns its own Mode
  system, CK/Autolearn/KaiokenTrain bots are no longer mutually exclusive —
  run one bot at a time.

## CK-side removals

`Bots/Kaioken.lua`, the `kaioken train` alias, the `Prompt Kaioken` trigger +
script, the `Status mastered kaioken` child trigger, the `PromptFlags.Kaioken`
block in `Prompt_Events.lua`, and the `Kaioken` mode enum entry/branch.

## Testing

Same guards as Autolearn: `tools/lint_manifests.py` (muddler silently attaches
empty scripts for missing .lua files) and a fengari-based Mudlet simulation
(`tests/`) driving connect → MSDP → prompt/kaioken parsing → toggle → raise /
drink / rest / wake / completion, wired into CI.
