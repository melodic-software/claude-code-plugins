# /planning:interview Checklist — plugin-marketplace-code-clarity

Topic: a potential new skill (or extension of existing skills) covering comment removal
in favor of self-describing, expressive code, in this plugin marketplace.

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect — routed to Q&A (real design decisions with no codebase answer)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Recognize the stop condition
- [ ] Step 4: Persist the contract
- [ ] Step 5: Hand off

## Survey notes (what exists today)

- `code-tidying:audit-comment-residue` — read-only classifier, 4 residue shapes
  (history-narration, plan-reference, conversational-antecedent, ticket-pr-residue).
  Explicitly NOT restating-the-code redundancy.
- `code-tidying:tidy` — Beck tidying #15 "Delete Redundant Comments" (applies edits,
  conservative) and #14 "Explaining Comments" (add why-comments); prose variants P-5/P-6.
- `naming:name-it-better` — expressive name generation for an undecided name.
- Marketplace doctrine already on record (audit-comment-residue Sources): the
  Ousterhout ⇄ Clean Code debate — positive rule is "a comment captures what the code
  cannot (non-obvious why, constraint, interface/design-intent contract)."
- Gap: nothing that actively TRANSFORMS comment-laden code toward self-describing code
  (Fowler: "when you feel the need to write a comment, first try to refactor so the
  comment becomes superfluous") — i.e., extract-function/extract-variable + renaming
  driven by *what*-comments, then deleting the now-redundant comment.

## Open-question register

- Q1 | open | round 1 | What prompted this — agent-written diffs, legacy sweeps, or standing posture? |
- Q2 | open | round 1 | Deliverable shape — new code-tidying skill vs tidy extension vs rule/posture? |
- Q3 | open | round 1 | Doctrine — where on the Ousterhout ⇄ Clean Code spectrum; which comments survive? |

## Decision tree (`me` mode)

- [ ] Motivation / primary use case (Q1)
- [ ] Deliverable shape (Q2)
- [ ] Comment doctrine + aggressiveness (Q3)
- [ ] Mode: audit-only vs applies edits (blocked by: Q2)
- [ ] Trigger surface: on-demand vs proactive/standing (blocked by: Q1, Q2)
- [ ] Plugin home + name (blocked by: Q2)
- [ ] Overlap fences vs audit-comment-residue / tidy #14-#15 / naming (blocked by: Q2, Q3)
- [ ] Ecosystem scope + detection approach (blocked by: Q2)

## Session-shorthand glossary

- *residue* — out-of-context comments (history/plan/conversation/ticket refs), the
  existing audit-comment-residue territory; distinct from *restating* comments.
- *what-comment / why-comment* — a comment describing what the code does (candidate
  for refactor-away) vs why it does it (keep).
