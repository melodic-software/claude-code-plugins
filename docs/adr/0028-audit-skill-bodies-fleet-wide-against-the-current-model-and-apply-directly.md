# Audit skill bodies fleet-wide against the current model and apply the findings directly

- Status: accepted
- Date: 2026-09-02
- Supersedes: [ADR-0004](0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md) decisions D-1 and D-3, for the skill-body audit lane only; the promotion gate of [ADR-0006](0006-scope-model-doctrine-per-version-behind-a-promotion-gate.md) as retained by [ADR-0007](0007-host-per-model-doctrine-outside-skill-private-surfaces.md), for applied prompt-audit findings only

## Context

Claude Code ships a `prompt-audit` procedure inside its bundled `claude-api` skill. It reads
an instruction surface against a named target model, classifies each dated pattern into one
of four groups (obsolete scaffolding, brittle history and volatile specifics, worked examples
that constrain, and request-building code the model executes by hand), and prescribes a
concrete action per finding: remove, rewrite, move, replace with an API feature, add, or flag.
Its keep list is as binding as its pattern tables, and it states that an audit which finds
nothing changes nothing.

In September 2026 the operator ran that procedure over every skill in this marketplace with
Claude Fable 5.1 as the target model. The run is recorded in
[`docs/specs/prompt-audit-skills-2026-09.md`](../specs/prompt-audit-skills-2026-09.md): one
fresh-context auditor per plugin, one report per plugin, the lead's per-finding decisions, one
commit per plugin with a patch bump and evals updated in step, and a follow-up inventory. The
sweep closed on 2026-09-05 over all 74 plugins: 63 took a commit and 11 were clean (one
single-skill plugin and ten whose only in-scope file the setup lane had audited). Across the
64 reports the lead applied 805 finding ids and withheld 207, the withheld set listed in the
record by plugin. The branch changed 694 files under `plugins/`, and no skill lost a step, a
gate, or a safety refusal in the record's five-skill behavioral spot-check.

Three accepted decisions stood in the way, and the operator ruled before the first wave that
none of them binds this lane:

- **ADR-0004 D-1, the incumbent-first gate.** No remediation ships until it proves no existing
  skill already covers it. A prompt-audit finding is a text defect at a `file:line`; its
  remediation is the hunk the procedure prescribes. An incumbent search per hunk would cost
  more than the hunk and answer a question the procedure already answered (the pattern table
  is the incumbent).
- **ADR-0004 D-3, no bulk sweep of `plugins/**`.** Findings were to land as checks in the
  plugin that owns each surface, never as a sweep. That decision was written for a
  practitioner article whose claims were a third unbacked. The prompt-audit guide is the
  vendor's own procedure for the vendor's own model, and its findings are edits, not
  criteria. Landing them as checks would leave every body unchanged.
- **ADR-0006's promotion gate, retained verbatim by ADR-0007.** Doctrine sourced from a single
  model's guide is model-scoped by default and reaches fleet-wide only when a model-agnostic
  upstream document states the claim or several model guides converge on it. The audit labels
  every finding `fleet` or `fable-5-1`. Applying only the `fleet` set would leave the
  `fable-5-1` set, which exists precisely because the target model changed, unapplied on the
  model it targets.

ADR-0004 D-15, arbitration over blanket deletion, was honored in form: every applied finding
carries the constraint's rationale and why it no longer holds for the target model, and the
guide's keep list (exact scripts for fragile operations, safety gates, working redundancy)
was applied as written. Two further ADRs were checked and left accepted:
[ADR-0005](0005-bound-instruction-surface-work-by-question-not-population.md) bounds
instruction-surface work by the question it asks, and this lane asks one question (is this
passage a dated prompting pattern for the target model), so it is consistent.
[ADR-0008](0008-admit-only-present-text-defects-to-the-instruction-audit-catalog.md) governs
what enters the `audit-instructions` catalog; this lane edits bodies and records catalog gaps
without adding rows, so it is consistent. Whether either should retire on other grounds is the
operator's call at PR time and is not decided here.

## Decision

**A skill-body audit against the current model runs as a fleet-wide sweep and applies its
high and medium confidence findings directly**, one commit per plugin, without an
incumbent-first gate and without scoping applied findings to the model that motivated them.

The procedure is the bundled `prompt-audit` guide at the Claude Code version that ran it,
with the target model named at Step 0. Where the migration guide carries guidance for a prior
model and none for the target, the prior model's guidance applies; on conflict the target
model wins.

Three rules travel with the decision:

1. **Labels are recorded, not gated.** Every finding carries `fleet` or `fable-5-1`. Both are
   applied. The label exists so a consumer on another model can read what changed and why;
   it does not decide whether the change ships. The promotion gate of ADR-0006 continues to
   govern the `playbooks` model-adaptation chapters and the `audit-instructions` catalog's
   `Model scope` rows, which are doctrine surfaces. It does not govern edits to skill bodies
   that remove a pattern the target model no longer needs.
2. **Repo conventions yield to the procedure inside the lane.** A CI gate or a static check
   that blocks a warranted change is changed in the same commit, and the change is recorded in
   the run's record. The first instance is `skill-quality`'s check 3, which hard-failed any
   dropped trigger phrase and so blocked the guide's Group 2 fix for trigger-case
   enumeration; it is now advisory.
3. **Skill bodies state current rules.** The path-scoped rule
   `.claude/rules/skill-bodies-state-current-rules.md` codifies the guide's Group 2 for
   `plugins/*/skills/**` and `plugins/*/agents/**`: a body carries the rule and its reason
   in the present tense, and history belongs in the CHANGELOG, the commit, and `docs/adr/`.

Mechanism changes the audit exposes (extracting a hand-executed shell block into a script,
adding a pre-compute block, parameterizing a hardcoded vendor) are follow-ups, not audit
hunks. The record inventories them and the PR body carries them verbatim.

## Consequences

**Bodies change fleet-wide in one PR, and the diff is large.** The record is the reviewable
unit: each plugin's row names its commit, its applied and withheld finding ids, and the
trigger phrases it deliberately dropped. A reviewer who wants the archaeology reads the
report the record points at; the body no longer carries it.

**The incumbent-first gate loses its blanket status.** ADR-0004 D-1 still binds lanes that
propose new machinery, where a duplicate is the risk. It no longer binds text-defect lanes
whose remediation is a prescribed hunk. The cost is that a future sweep can apply a hunk an
existing check would have caught differently; the record's catalog-gaps section is where that
shows up, and the `audit-instructions` catalog is extended from it under ADR-0008's
admission rule.

**Fable 5.1-specific edits are live on every model.** A consumer running an older model reads
bodies tuned for the current one. The label in the record says which edits those are, and the
`playbooks` adaptation chapters remain the place to counter-steer per model. This is the
trade the operator chose over leaving the target model under-served.

**Trigger phrases can be dropped on purpose.** Check 3 warns instead of failing, so a
description that consolidates near-synonyms into an intent category ships with the warning
recorded. A reviewer confirms the intent is still named or restores the phrase; the check no
longer decides.

**The audit repeats per model change.** The playbooks' own regeneration trigger fired with
Fable 5.1 (record follow-up F14). Each future target model re-runs this lane from the
record's method section, with the previous run's withheld items as the first candidates.
