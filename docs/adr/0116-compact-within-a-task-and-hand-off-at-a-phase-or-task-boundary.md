# Compact within a task and hand off at a phase or task boundary

- Status: accepted
- Date: 2026-11-21
- Supersedes: the "Between human stages" rule of the continuation router, added in
  [#12861](https://github.com/melodic-software/claude-code-plugins/pull/12861) (a handoff between
  the interview, PRD, design and plan stages only at zone `heavy` or on the compaction marker)
- Related: [ADR 0115](0115-write-handoff-shape-4-with-binding-sections-first-and-a-tool-owned-byte-budget.md)
  (handoff shape 4), [#17877](https://github.com/melodic-software/claude-code-plugins/issues/17877)
  (post-merge checklist)

## Context

The owner wants a handoff to work as a lossless compaction across a session boundary, and
compaction itself kept for continuing one task (owner, 2026-11-18). Before this change the
continuation router compacted "the related next task", so one plan phase flowed into the next in the
same session, and it kept the interview, design and plan stages in one session unless the window was
`heavy`. Long sessions crossed several stages on summaries of summaries.

## Decision

1. **Within one task, compact.** The router's fallthrough (question 6) is the same phase, activity
   or task, and recommends `/compact <focus>`, repeatable when the window needs it.
2. **At a phase or task boundary, next in sequence, hand off then `/clear`.** Question 5 covers the
   interview into design, one plan phase into the next and a finished spec or plan into execution,
   whatever the zone (owner, interview Q34: "same task compacts; a phase or task boundary, whether
   the next item in a sequence or unrelated work, hands off then clears; a plain /clear when nothing
   carries over").
3. **Unrelated work is unchanged:** a handoff when something carries over, a plain `/clear` when
   nothing does (question 4).
4. **The "Between human stages" zone rule is removed** (owner design Q3: the router change replaces
   it).

## Consequences

- A boundary costs one handoff write and one resume. Shape 4 keeps that resume small: AC16 measured
  the first call at 97,999 tokens after, 98,090 before, about 92k of it startup.
- The statistical compaction gates planned before this change were dropped for cost. It ships on the
  deterministic content check and the paired smoke shape 4 shipped on, the unit tripwire, and the
  review lanes (owner, 2026-11-21: "just fucking stop the evals, get the shit pushed in and
  merged"). The `wf-*` routing cases and the real-session check (AC9) return with the eval work.
