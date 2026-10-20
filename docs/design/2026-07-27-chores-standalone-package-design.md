# Chores Standalone Package — Design

Date: 2026-07-27

Third standalone module (after Autolearn and KaiokenTrain): automated fishing
and a recurring delivery quest, in one package.

## Shape

- Package `Chores` (muddler project at repo root `Chores/`), global prefix
  `CH`, own `Chores` settings DB, own `CH.*` events. Vendored minimal core
  (KaiokenTrain-sized: init, Core, MSDP, prompt lifecycle, connection events)
  — no skills/attacks/fight model.
- Command: `chores <fish|quest|both>`, `chores off` (or bare `chores`).
  Plus `CH` help, `CH features/constants`, `CH update`.
- CK's `Auto Fish Reelin` / `Auto Fish Retry` triggers move into this package
  and out of CK.

## Fishing loop (modes fish/both)

- `castout`; on "You feel a tug on your line!" → `reelin` then `castout`
  (user confirmed reelin always lands the fish — no catch message needed).
  When the bot is off, the tug still auto-reelins (parity with old CK).
- Tangle lines (CK's long form and the short "Your line gets tangled. Try
  again.") → `castout`.
- Heartbeat: no tug for `chores.recast_timeout` (default 120s) → re-cast.
- Fatigue: below `chores.rest_below` percent (default 20) → send
  `chores.rest_path`, `sleep`; at full fatigue → `wake`, `chores.fishing_path`,
  resume casting.

## Quest cycle (modes quest/both, every `chores.quest_period` min, default 5)

Preempts fishing (and wakes from rest — quest has priority; fatigue check
re-rests afterwards if needed):

1. `recall`, then `chores.instant_cmd` (default `focus 'instant' roshi`)
2. Wait for the Roshi room line; on timeout retry the instant up to 3 times,
   then abort back to fishing
3. `pursue royal cook`; on "would you be able to deliver some rations" → `yes`
4. On "This must go to Sir <Name>" → `pursue <name>`, `give jerky <name>`
   (knight keyword = lowercased last name; cook hands over the jerky on accept)
5. On "I just sent you on a delivery N minutes ago" → next attempt in
   (period − N) minutes instead of a full period
6. Return via `chores.fishing_path` only (no recall — user's paths are
   authored to work from the quest end and the rest room)

Every step has a deadline; any timeout aborts the cycle and resumes fishing.
The bot must never end up parked somewhere odd.

## Boss fish (placeholder)

Constants `chores.boss_before`, `chores.boss_attack`, `chores.boss_after` and
two INACTIVE triggers with placeholder patterns (`Chores Boss Fish`,
`Chores Boss Dead`) wired to a fight routine: send before-commands, spam the
attack each tick, on death send after-commands and resume casting. Goes live
once the user supplies the real appear/death lines.

## Testing

Same guards: `tools/lint_manifests.py` + fengari simulation driving the whole
loop (cast/tug/tangle/heartbeat/rest/wake, quest happy path, cooldown
reschedule, Roshi retry-then-abort, quest-preempts-rest, boss routine, mode
switching), wired into CI.
