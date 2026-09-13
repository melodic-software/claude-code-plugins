# audit-pass: the lane catalog

This file owns the Phase 3 dispatch catalog: every lane the pass dispatches, what each delegated
skill owns, why each one is exactly one lane (or one lane per surface-class value), what is
deliberately not dispatched, and the substrate probe that decides whether a lane can verify itself.
What a lane *is*, what earns one, the lane ids `--lanes` names, per-lane persistence with the
exit-3 fence, and the concurrency cap stay in Phase 3 of [`../SKILL.md`](../SKILL.md).

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md). Finding identity:
[finding-identity.md](finding-identity.md).

## The lanes

Dispatch, in inventory order, with every skill below invoked via the Skill tool, each invocation
presence-gated with its fallback stated:

- **`/claude-config:audit-instructions`**: sibling in this plugin, always available. Carries the
  model-capability catalog over every non-memory surface, and the cross-surface conflict check. It
  takes a **surface-class scope**, so the per-class values yield **one lane per scope value
  dispatched**, each running that skill's per-surface catalog over that class. Its conflicts come
  back as **one finding carrying two sites**, never two linked findings, since a contradiction is retired
  by fixing either side, so the sides are not independently correctable.

  **The conflict pass is dispatched exactly once, as its own lane, via that skill's `conflicts`
  scope, never once per surface class.** Its unit is a *pair*, and its Phase B2 reports a pair
  whenever **at least one** anchor falls in the requested scope, so a conflict spanning a skill body
  and an agent definition would be returned by the `skills` lane *and* the `agents` lane. Both would
  carry the same identity, and the partial-log contract assembles per lane with no cross-lane
  ownership rule, so the finding would land in the report twice. Its own scope makes every pair
  belong to exactly one lane by construction rather than needing a deduplication rule downstream,
  and the per-class lanes drop the pair check, since dispatching it there is what created the
  overlap.
- **`/claude-config:audit-permission-state`**: sibling in this plugin, always available. It owns the
  permission plane as it is *in effect*: the merged allow/ask/deny set with per-rule provenance,
  what auto mode drops on entry, configuration written where nothing reads it, and which managed
  intents are enforced versus loosenable. It takes an **action flag and no target**, so it is
  **exactly one lane** covering all of that.

  **Its managed-scope reads belong to the pass's read-only managed inventory, not to a project lane.**
  It reads managed policy on every OS and never writes anywhere, in any scope, under any flag, so it
  is safe to dispatch under the pass's bare invocation. Its `--oracle` path spawns a real session and
  is **never dispatched here**: the pass has no way to price that for the operator mid-run, and the
  flag exists to make the cost an explicit choice.

  **Its optional lanes degrade rather than fail.** The `autoMode` block lane needs `python3` and
  `claude` on PATH; absent either, that lane self-reports as skipped and the rest of the skill still
  runs. Carry that skip into the report as **unchecked with its reason**, exactly as an absent plugin
  would be. The distinction between "clean" and "not read" is this skill's whole contract and the
  pass must not collapse it.
- **`/claude-config:audit`**: sibling in this plugin, always available. It owns config-file
  correctness: settings, hooks, plugins, permissions, MCP servers, environment variables, the
  skill-listing budget, model and effort values, and deep-link registration. It takes a **category
  scope and no surface filter**, so it is **exactly one lane** covering its whole catalog. Its
  engine persists a findings document whose rows already carry this pass's identity tuple
  (`check`, `claim`, `sites` of `surface` plus `anchor/v1`) with `lane` and `tier` set, so the lane
  appends each row of that document through `partial append` **unchanged**, adding only the
  `attempt` id; a row is never re-derived, re-hashed, or re-severed here. Engine rows are
  derived-tier; the rows the audit's model adds for its judgment categories are judged-tier, and
  the document marks each. Its own suppression handling reads the same `.claude/audit-pass.md`
  record this pass reads, so a finding the audit reports as suppressed is carried into the
  `suppressed` section with its reason, never raised twice.
- **`/claude-memory:audit`**: invoke when the `claude-memory` plugin is installed; it owns
  memory-layer hygiene and the within-memory-layer consistency check. It takes an **action verb and
  no surface filter**, so it is **exactly one lane** covering the whole memory layer. Not installed:
  the pass reports both as **unchecked**, names that skill as their owner, and emits the one-line
  pointer to the official memory guidance, never a silent skip and never a re-implementation here.
- **`/claude-config:audit-permission-grants`**, `frontmatter` scope: sibling in this plugin, always
  available. It takes a **scope filter**, and only the `frontmatter` value is dispatched here, which
  makes it **exactly one lane**. That scope audits `allowed-tools` blocks in skill, command, and
  agent frontmatter, which the Phase 1 inventory already enumerates as instruction surfaces, so it
  meets the what-earns-a-lane criterion Phase 3 of [`../SKILL.md`](../SKILL.md) states. Its
  settings-file scope is **not** dispatched: the permission plane as
  it is in effect belongs to `audit-permission-state`, and running both over settings would report
  one plane twice under two identities.

  **It is admitted for what its output is, not for how many findings it happens to return today.**
  The lane is a deterministic script over frontmatter the pass already inventories, so it is cheap,
  its rows are **derived tier**, and it is the first lane that adds derived-tier volume. That last
  point is the structural one: P1 is defined over the derived tier, so a pass whose derived tier is
  near-empty gives the determinism gate nothing to bite on, and a gate with no subject is a gate
  that cannot fail. A lane's worth here is its contribution to what the gate can compare, which does
  not move with the current defect count in any one repository. Read-only, and never dispatched with
  a fixing argument.
- **Retired-conventions fleet sweep**: the one script lane, **exactly one lane** running this
  plugin's canonical `lib/check-retirements.sh` over every installed plugin's `retirements.yaml`. One finding per active TSV row keyed by record id; `report-only` = `info`; helper exit 2 = FAIL finding, never a skip.
  Derived-tier, **read-only** (never `--clean`); rest: [retired-conventions-sweep.md](retired-conventions-sweep.md).
- **`/claude-config:audit-prompting-postures`**, dispatched **only under `--postures`**: sibling in
  this plugin, always available. It takes an action and no surface filter, so it is **exactly one
  lane** covering its whole posture catalog. It is the additive lane, proposing guidance a component
  does not carry rather than reporting defects in what it does, and it fans out over every
  instruction component in the target, which is why it is opt-in rather than default. Its findings
  are judged tier. Without the flag the lane is reported in `skipped` with `--postures` named as what
  would run it, never omitted, because an absent section reads as a clean one.

Structural skill lint is deliberately **not** dispatched: it answers shape rather than content, and
its fan-out over a large corpus would consume the dispatch budget reserved for instruction-content
lanes. Route it out (`skill-quality:check` when installed).

## The dispatch substrate is probed, never asserted

**Whether a lane can spawn its own verifier is a property of this host's depth budget, not of Claude
Code.** Subagent nesting is available by default to a documented depth, and a host lowers or removes
it through `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`. Writing either shape into this body as though it
were harness behavior would be the same defect class this plugin's own catalog flags: an instruction
surface misstating what the harness does, which then outlives the configuration it described.

> **Verified 2026-09-13**, Claude Code 2.1.268. **Claim:** subagents may spawn subagents by default
> to a bounded depth, and `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is the environment variable that
> lowers that budget, a value of 1 disabling nesting. **Basis:**
> [subagents](https://code.claude.com/docs/en/sub-agents) and
> [settings](https://code.claude.com/docs/en/settings) (environment variables). **Recheck trigger:**
> the documented default depth changes, the variable is renamed or retired, or nesting stops being
> on by default.

So the run **probes** rather than assumes, and records what it found:

- **Depth budget allows nesting.** Per-lane verification runs inside the lane, which is where it
  belongs, since the lane's own findings are what it judges. The lane's terminating record says
  `verified`.
- **Depth budget does not allow nesting.** The lane cannot verify itself and records `inline`. It
  does not fail, and its findings are not suppressed; they carry the `(unverified)` marker and the
  main-session pass in Phase 6 of [`../SKILL.md`](../SKILL.md) picks up what it can.
- **Probe inconclusive.** Treated as the second case. A verification recorded on an unestablished
  capability is worse than one honestly marked `inline`.

The probe is cheap and its result is a run-level fact, so it is taken once before the first dispatch
rather than per lane, and recorded in the report beside the per-lane modes.
