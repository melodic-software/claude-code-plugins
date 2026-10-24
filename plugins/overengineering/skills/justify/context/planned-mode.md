# Planned mode: a proposal, before it is built

The item is a proposal: a plan step, a design option, or a described mechanism such as "a branch, a
workflow to move it, and a ruleset to protect it". The question is whether each thing it adds is
needed at all.

## The rule

A mechanism that an existing control already covers, or that serves no stated requirement, is
overengineering. An abstraction for a stated, known repetition with a namable shape is not.

The consuming repository's standards draw that line; read them where they live rather than from
memory. Resolve the standards index (`docs/standards/README.md`, unless `.claude/standards.yaml`
sets `standards_dir`) and read two entries: `simpler-code`, section "Named failure modes to avoid"
(speculative generality, YAGNI), and `reference-dont-duplicate`, section "Consolidation doctrine:
ordered tests" (T3 to T5, where an abstraction is namable and stable). With neither entry, apply the
rule above as written.

## The test

1. **List every mechanism the proposal adds**, one line each: a branch, workflow, ruleset or
   protection rule, app or bot identity, service, file, dependency, check. A mechanism that exists
   only to protect or run another is listed too; it stands or falls with what it serves.
2. **Name the requirement or risk each one serves**, as the proposal or the user states it. A reason
   such as "for safety" names no risk until the risk is named; ask rather than infer one.
3. **Find the existing control that already covers the same risk**: CI checks and tests, branch
   protection, hooks, existing workflows, configuration, a documented process. Read it and cite the
   `file:line` or tool output. Vary the query form before claiming there is none, per
   `justification-lane.md` section 7, first bullet.
4. **Give each mechanism one verdict:**
   - `drop: use <existing control>`: an existing control covers the same risk.
   - `drop: no stated requirement`: it serves a requirement nobody stated.
   - `keep`: it serves a stated requirement no existing control covers, including an abstraction for
     a stated, known repetition whose shape is namable and stable.
   - `UNPROVEN`: the requirement or the coverage cannot be established. Name what would settle it
     and ask, as the skill's "Intent checkpoints" section says.
5. **Count moving parts.** Count the mechanisms each option adds: the proposal as given, the
   proposal without its dropped mechanisms, and any alternative the user named or the existing
   controls suggest. Recommend the option with the fewest that still covers every stated risk.

## Gotchas

- **Compare risks, not objects.** A control on a different object can cover the same risk:
  protection and a test gate on the default branch cover a proposal to protect a copy of it.
- **A stated second consumer is not speculation.** When the requirement for the second use is
  already stated and the shared shape can be named, the abstraction is `keep`; do not ask for a
  third occurrence the standards do not demand.
- **The proposer's framing is not evidence.** A proposal arriving with "we need this" attached is a
  hypothesis to test, as it is for an existing artifact.
