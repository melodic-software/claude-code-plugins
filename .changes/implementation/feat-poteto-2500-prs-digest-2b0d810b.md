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
- **Competing attempts for a phase the plan marks `multi-shape`.** `/implementation:implement-dispatch`
  gains a "Competing attempts" section: for a marked phase it creates one local worktree per attempt
  on `<branch>-attempt-<n>`, briefs each attempt with its own constraint from the plan, gives each a
  phase-verifier, picks among the passing ones by the plan's written selection rule (recorded as
  `attempt <n>: chosen by <rule clause>` or `attempt <n>: set aside by <rule clause>`), lands the
  chosen one with `merge --ff-only`, and removes the attempt worktrees through
  `/source-control:worktree cleanup` when it is available, keeping the branches. Attempts commit
  locally and never push, count against the wave cap, and run on `/multi-agent:route`'s worker
  fan-out model floored at the implementer binding (frontier attempts one at a time). When every
  attempt fails, the run routes back to planning with each verifier's gaps. `competing_attempts`
  sets the mode: `suggest` (the default) offers attempts on a marked phase with a cost line, and an
  unattended run makes one attempt and logs a `discovery` entry; `auto` runs them without asking;
  `off` ignores the mark. `competing_attempt_count` sets how many, a whole number from 2 to 5
  (default 3). Both are set per user in new user config options and per repository in
  `docs/conventions/implementation.yaml` (schema `schemas/implementation.schema.json`), which wins;
  an invalid value is named and that layer dropped. An older release has no option for either key
  and ignores the repository keys. Thirteen eval cases cover the modes, the layers, the model floor,
  the frontier limit, no push, the all-fail route, the fast-forward landing and the cleanup.
- **Refactor mode holds a phase's parity contract.** When the plan phase carries a
  `**Parity contract:**` line and `/testing:check-visual-parity` is among the available skills,
  `context/refactor.md` runs its `baseline` for the listed screens and states before the first
  structural edit and its `compare` at each green checkpoint, and treats a failing compare as a
  behavior change to investigate. One eval case covers it.
- **`/implementation:implement-dispatch` refuses unscoped briefs and keys verdicts to the head
  SHA.** It holds back any brief with a gap the plan, Brief and design leave open, names the
  missing items, and routes the row back as a divergence. Every brief carries a
  `Structure:` line naming the data structure the new logic is built on. A resumed run opens its
  `DEVIATIONS.md` additions with a run-boundary entry naming the session and the entries it did not
  write. Each phase verdict is recorded against the head SHA it judged, and a rebase or new commit
  before `[DONE]` voids it. An operator hold stops every running dispatched agent with `TaskStop`
  and dispatches nothing more. A gamed gate gets a tighter contract and a wrong gate a separate fix.
  Workers run where the session runs; cloud placement is the execution-target contract's. Five eval
  cases cover the refusal, the run-boundary entry, the head-SHA verdict, the structure line and the
  hold.
- **Refactor mode subtracts first and keeps a reshape only when reading gets easier.**
  `context/refactor.md` gains a subtraction step that lists unused imports and config keys,
  single-caller wrappers and unreachable branches (through `/code-tidying:audit-dead-code` when it is
  among the available skills, else a grep for callers) and commits their deletion first; says a
  passing typecheck or lint is not a pin; keeps a move only when it removes a branch or an invalid
  state, never when it only adds indirection; never edits a test, baseline or harness to go green
  and asks instead, except that a plan-declared contract change retargets or deletes the
  old-contract tests; and ends by naming where reader load fell or reverting. Under
  `refactor_compat: deprecate` each kept adapter also names a time box and a follow-up item. Four
  eval cases cover them.
