# audit-instructions improvements

## Brief

### TLDR
- Execution model: lanes sized by a token budget stated as a fraction of the lane model's window, plugin-atomic with a split-by-skill overflow, an explicit `--unattended` flag, and `--resume` over per-lane run files guarded by the sibling `run-state.sh` lease and an input digest (one PR).
- Scanner calibration: the I6 pre-scan adopts the `audit-noise` imperative-opening gate set; I33 keeps one finding per spoke under an excerpt anchor, the lane brief restates the row's fences, the report rolls up per plugin in presentation only, and one class-batched verifier judges the class.
- Report contract: findings adopt the `(check, claim, sites)` identity with a claim template per check; four crosswalk rows admit I30, I31, I32, I33 to `--persist-findings` as `Auto-applicable: No` through a lane-fed emit path.
- Environment fit: two sentence-level `SKILL.md` fixes ship in their own small PR; the guardrails block message gains the shipped temp-tree route and the variable-carried residual.
- Findings filing: one I32 routing issue and one I28 batch issue now; the remaining retained findings wait for the identity contract and a re-run.

### Goal
A full run of `/claude-config:audit-instructions` over a marketplace-sized repository finishes inside one session's budget or resumes cleanly after an interruption, asks nothing when the caller declares the run unattended, seeds its lanes with a pre-scan whose candidate count is within an order of magnitude of what survives, reports the largest info class without burying the operator, and emits findings whose identity is stable across runs so they can be filed, suppressed, and re-checked.

### Constraints
- The skill stays report-only: no `--fix`, no edit to any audited surface during a run, and the Read-only contract in `SKILL.md` is unchanged.
- Every proposal is verified in Phase C. No sampling, no exemption for a finding class that carries a diff.
- Reuse over reinvention: the run-state lease comes from `plugins/claude-config/skills/audit-pass/scripts/run-state.sh` (promoted to `lib/` or invoked with its `--plugin-data` pin), finding identity from `audit-pass/reference/finding-identity.md`, report keying from `docs/conventions/plugin-data-report-keying`, and crosswalk admission from `docs/conventions/detector-findings`. Never a silent second way.
- Guardrails hook edits respect `.claude/rules/hook-budget.md` and keep the guard's pinned test assertions green; no parser change to follow shell variables.
- Skill and agent bodies state the current rule and its reason, never the incident (`.claude/rules/skill-bodies-state-current-rules.md`); no em dashes in instruction surfaces.
- Every PR opens as a draft, carries the PR body contract, closes exactly one sub-issue, and validates with `scripts/affected-tests.sh --run`.
- The I33 row keeps its tier (`info`), authority (`HOUSE`), Detect, and Remediate text.

### Acceptance criteria
- IF a plugin's in-scope surface text exceeds the lane budget, THEN that plugin's skills are partitioned across lanes by skill and the cost line names the split.
- WHILE a live lease exists under the run's state key, `--resume` refuses to attach and names the lease's `heartbeat_at` and `stale_after_s`.
- IF `--unattended` is absent and the planned dispatch count would exceed about 20, THEN the run asks before dispatching; IF `--unattended` is present, THEN the run proceeds and the cost line discloses the count.
- A `--resume` after an interrupted run re-runs only lanes whose completion marker is absent or whose input digest changed; changing the catalog version, the conflict-criteria version, the prompt digest, the harness version, the resolved target model, or any behavior-affecting argument re-runs every lane.
- Lane report files live at `${CLAUDE_PLUGIN_DATA}/audit-instructions/runs/<state-key>/<run-id>/lanes/<lane-id>.md`, and `last-audit.md` stays at `audit-instructions/<state-key>/last-audit.md`.
- `scripts/instruction-scan.test.sh` has passing cases for the imperative-opening gate, the paired-positive boundary, soft-wrapped sentence accumulation, and fence and table exclusion; the report states raw and surviving I6 counts.
- On this repository at HEAD `2dfaaa40`, the I6 seed count falls below 1,000 rows (from 6,476) with the five retained findings still seeded.
- Lane-brief fixtures with a one-line scope note and a hub index pointer produce zero I33 findings; the Phase D report carries a collapsed per-plugin I33 section whose rows keep `Surface:Line` and a diff.
- Two runs over an unchanged tree yield identical `finding_id` values; editing an I33 opener changes that finding's id; a cross-surface I15 conflict is one finding with two sites.
- `scripts/check-detector-findings-crosswalk.sh` passes with the four new rows; `--persist-findings` emits I30, I31, I32, I33 rows from lane findings with a `Confidence` value the contract defines for a model-lane finding; frontmatter-located I32 rows are declined and counted, never dropped silently.
- The guardrails block message names the shipped temp-tree literal-path route and states that a variable-carried or quoted operand is never exempt; `block-hook-bypass.test.sh` passes; the guardrails CHANGELOG and manifest bump pass `scripts/check-changelog-parity.sh --check-bump`.
- `SKILL.md` Phase B tells lanes to write reports with the Write tool or to a literal absolute path under the shipped scratch roots, and states the `--unattended` behavior of the dispatch gate; `scripts/affected-tests.sh --run` passes.
- `reference/conflict-criteria.md` "Known limit" states the marketplace scope rule: `.claude-plugin/marketplace.json` present means `plugins/**` is the editable set, the installed cache is read for residency, and the report names cache-commit versus HEAD drift.

### Captured assumptions
- The headless flag is spelled `--unattended` (the interview skill's "declared by the caller, never sniffed" wording) rather than `review:fanout`'s `--yes`; revisit if the fleet standardizes one spelling.
- The lane budget fraction and the bytes-per-token estimate are chosen at implementation time and stated in the skill body as measured; revisit if any lane overflows its window on a supported model.
- The acceptance-criteria coverage prompt was not put to the user; the unwanted-behaviour and state-driven cases above were authored from the validators' findings; revisit at `/planning:plan` approval.
- Whether `run-state.sh` moves to `plugins/claude-config/lib/` or is invoked in place with `--plugin-data <plugin-data>/audit-instructions` is an implementation choice; revisit if a third skill needs the lease.
- The I32 routing issue asks, rather than decides, whether `skill-reference-verify` should widen its extraction or scan resting text; revisit when the guardrails owner answers.

### Out-of-scope
- A parser change to `block-hook-bypass` that resolves variable-carried redirect targets.
- Filing the roughly 324 retained findings outside I32 and I28 before the identity contract lands.
- Sampling or skipping verification for any finding class.
- A cross-vendor advisor for Phase C.
- Memory-hygiene checks I1 through I5, which route to `/claude-memory:audit`.
- Changing the I33 row's tier, authority, Detect, or Remediate.

### Deferred questions
- None: every register row (Q1 through Q21) is answered; no row is deferred or blocked.

## Plan
