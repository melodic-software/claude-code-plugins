---
bump: minor
---

### Added

- **No suppression to make a check pass.** `/implementation:implement` "Commit discipline" and the
  `/implementation:implement-dispatch` worker brief both carry the rule: adding a lint or
  type-checker suppression to turn a check green is not allowed, except for a proven false positive
  whose suppression line states the reason and, where the tool can name one, the rule id. A
  project's own instructions may override it. One eval case per skill.
- **`refactor_compat` sets what a refactor does with the shape it replaces.** `same-wave` (the
  default) updates all call sites and removes the replaced shape in that same change, unless code
  outside the repository (a public API, a published package) relies on it; `deprecate` keeps an
  adapter with a removal condition for every consumer. `/implementation:implement` refactor mode
  resolves it in `context/refactor.md` and reports the supplying layer. It is set per user in the new
  `refactor_compat` user config option and per repository in `docs/conventions/implementation.yaml`
  (schema `schemas/implementation.schema.json`), which wins; an invalid value is named and that
  layer dropped. An older release has no option for it and ignores the repository key. Three eval
  cases cover the default, the `deprecate` option and the repository file winning.
- **`integration_posture` sets how far a change reshapes the code around it.** `by-kind` (the
  default) redesigns the code a feature lands in as though the feature had been there from the
  start, keeps a fix or a config change minimal, and keeps a refactor to the plan's scope with
  behavior unchanged; `day-one` and `minimal` override the feature, fix and config kinds, never a
  refactor. `/implementation:implement` Step 0 resolves and applies it only when no approved plan
  exists (with a plan, `/planning:plan` has already written any redesign as work items), and a
  non-interactive run whose kind is ambiguous takes `minimal` and appends a `DEVIATIONS.md` entry.
  Step 0's scope line now names fix and config modes, `context/feature.md` and
  `context/bugfix.md` read the resolved value, and `/implementation:implement-dispatch` brief
  item 3 carries it to each worker. It is set per user in the new `integration_posture` user
  config option and per repository in `docs/conventions/implementation.yaml` (schema
  `schemas/implementation.schema.json`), which wins; an invalid value is named and that layer
  dropped, and the skill reports the supplying layer. Five eval cases cover the no-plan default,
  the ambiguous unattended run, the repository file winning, and the `minimal` and `day-one`
  values.
- `/implementation:implement-dispatch` brief item 9: a worker that provisions its own worktree runs
  the consumer's Workspace environment `setup` for it, read from the fetched default branch and
  skipped when the item's input is untrusted.
- **`verify_mechanical_phases` sends every phase to the fresh-context verifier.** Off (the
  default), `/implementation:implement-dispatch` keeps the mechanical carve-out: the orchestrator
  verifies a mechanical, behavior-preserving phase from the diff plus the build/test signal, and
  that phase's fresh-context verdict is the PR's verify stage. On, `implementation:phase-verifier`
  runs for every phase, mechanical ones included. `/implementation:implement` reads the same key
  at Step 4 and, when it is on, has a fresh-context verifier check mechanical phases too. An
  invalid value is named and falls back to `false`. It is set per user in the new
  `verify_mechanical_phases` user config option and per repository in
  `docs/conventions/implementation.yaml` (schema `schemas/implementation.schema.json`); `true` in
  either layer wins, and the skill reports the layer that supplied the value. The new settings
  page `reference/config.md` holds the resolution and root rules, and a plugin-level eval case
  under `evals/` checks that a repository `true` dispatches the verifier for a rename phase.
- **Planned breakage tells a declared red step from a regression.** When the plan's phase carries a
  `**Planned breakage:**` line, `/implementation:implement` records the failure set at the span's
  start and allows a red commit only when every new failure lies in the declared paths or test
  filter, with a body naming the span; any other failure stops the run, and Step 5's end gate is
  always green. `/implementation:implement-dispatch`'s build gate and phase-verifier brief apply
  the same rule, and the early push carries a red commit only before a pull request exists.
- **`drain_cadence` lets a long dispatch run hold worker returns.** `on-arrival` (the default)
  keeps `/implementation:implement-dispatch` reading each return as it comes in. `batched` holds a
  return that arrives while the orchestrator is composing a wave's fences, running a build gate or
  making a phase-boundary commit, reads it when that step ends, and reads every held return before
  the phase is marked `[DONE]`; the wave cap is unchanged. It is set per user in the new
  `drain_cadence` user config option and per repository in `docs/conventions/implementation.yaml`,
  which wins; an invalid value is named and dropped.
- **`code_writing` chooses between inline editing and dispatch.** `inline` (the default) keeps
  `/implementation:implement`'s current detection. `dispatch` adds a third orchestration signal:
  after Step 1's prerequisite check, an interactive run hands every plan phase to
  `/implementation:implement-dispatch`, which writes worker rows for the phases the plan leaves to
  the main session and dispatches them as `implementation:implementer`. It is set per user in the
  new `code_writing` user config option and per repository in
  `docs/conventions/implementation.yaml`, which wins; an invalid value is named and dropped. A
  plugin-level eval case under `evals/` checks that a repository `dispatch` reaches
  implement-dispatch for a main-window phase.
- **A lever check runs before one change is applied at many sites.** `/implementation:implement`
  Step 2 gains a multi-site step: before a block that applies one change at three or more sites,
  it invokes `/discipline:script-the-deterministic-work lever-check` when that skill is among the
  available skills, which resolves the discipline plugin's `lever_scope` setting and answers
  `build-a-lever` or `edit-by-hand`; without it, the `deterministic` rule applies (a lever only for
  a mechanical change) and the run says so. A lever is piloted on one hand-edited site and diffed
  before it runs on the rest. `/implementation:implement-dispatch` runs the same check before a
  fan-out of one change and before its `/batch` offer, and when one run of the lever covers every
  unit it dispatches one worker row for the lever instead of one row per unit. The setting has one
  home, the discipline plugin; implementation declares no key for it. Three eval cases cover the
  hand-off, the fan-out and an unavailable discipline skill.
- **`per_unit_check` sets how a multi-site change is checked.** Once the lever or the hand edit
  is ready, `/implementation:implement`'s multi-site step applies it under this key. `pilot` (the
  default) changes a small first batch of units, checks them, then changes the rest with one check
  at the end; the batch size points at the Claude Code best-practices "Fan out across files"
  section. `every` checks each unit before the next. It is set per user in the new
  `per_unit_check` user config option and per repository in `docs/conventions/implementation.yaml`
  (schema `schemas/implementation.schema.json`), which wins; an invalid value is named and that
  layer dropped, and the skill reports the supplying layer. Three eval cases cover the default
  pilot, `every` and the repository file winning.
- **Fix mode commits the focused fix first and each sibling fix later in the same PR**, replacing
  the rule that fixed every sibling in one commit, and its report shows the red run before and the
  green run after. `/implementation:implement` also checks data at the system's boundaries, syncs
  the base before the first check, reverts a block that did not move the failing check (to the
  span's start inside a planned breakage), lists design signals, names the default delivery
  orders, and ends with the choices made and the open decisions; feature mode deletes dead code
  first, names a domain structure before growing a conditional, and sweeps for a changed contract.
  Five skill eval cases and three plugin eval cases cover them.
