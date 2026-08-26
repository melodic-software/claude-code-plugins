# L7 findings: `D-work-planning`

Slice audited: 95 `AGENT` rows (28 `T2`). Predicates emitted here: P7.

## P7 · a step defers a fact it needs to an unnamed location

### D-1 · `plugins/implementation/skills/implement/SKILL.md:71` (T2, S1)

Verbatim, step 4 of the Execution cadence:

> 4. **Commit checkpoint**. Commit after tests pass. Each commit should represent a green state. See below for commit discipline

The step commits. The rules governing how it commits are in `### Commit discipline` at line 83,
below the `### When to break the cadence` section that separates them. "See below" names neither
the section nor what the reader gets, so the step is executable without ever reaching the rules it
depends on. Predicate: P7, "the fact a step depends on belongs beside the step, not three sections
away."

Replacement for line 71:

> 4. **Commit checkpoint**. Commit after tests pass. Each commit represents a green state; message shape and granularity are in "Commit discipline" below

Severity S1: `T2` surface, and the deferred fact governs an action the step takes.

An alternative remedy, preferred if `L2-progressive-disclosure` is already restructuring this file:
move the `### Commit discipline` body up to sit directly under step 4, which satisfies co-location
outright rather than repairing the pointer. Pick one; do not apply both.
