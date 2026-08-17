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

- Q1 | answered | round 1 | What prompted this — agent-written diffs, legacy sweeps, or standing posture? | Agent-written code is the prime driver; on invocation the skill ENFORCES: remove comments, make code more expressive. Every surviving comment must earn its keep.
- Q2 | answered | round 1 | Deliverable shape — new code-tidying skill vs tidy extension vs rule/posture? | New skill inside code-tidying. Caveat: research must settle whether comment-removal and refactor-to-expressive are one concern or two (different criteria/rubric ⇒ maybe two components).
- Q3 | open | round 1 | Doctrine — where on the Ousterhout ⇄ Clean Code spectrum; which comments survive? | User leans Clean Code (Martin): no comments unless really necessary; self-describing code via names/parameters/structure. RESEARCH FIRST before locking — must reconcile with existing marketplace doctrine (audit-comment-residue cites the aposd-vs-clean-code debate).

## Decision tree (`me` mode)

- [x] Motivation / primary use case (Q1) — agent-written code, enforcement-on-invocation
- [x] Deliverable shape (Q2) — new code-tidying skill; one-vs-two-concerns pending research
- [ ] Comment doctrine + aggressiveness (Q3) — leaning Clean Code; blocked by: research
- [ ] Mode: audit-only vs applies edits (blocked by: Q2 conflation outcome)
- [ ] Trigger surface: on-demand vs proactive/standing (blocked by: Q1, Q2)
- [ ] Plugin home + name (home decided: code-tidying; NAME open — criteria locked: semantically correct, explicit over implicit, meaning obvious at invocation)
- [ ] Overlap fences vs audit-comment-residue / tidy #14-#15 / naming (blocked by: Q3, research)
- [ ] Ecosystem scope + detection approach (blocked by: Q2)

## Research dispatch (round 1.5)

Status: DISPATCHED via /discovery:research → discovery:researcher subagent (background).
Pre-dispatch gate probes OK; baseline `.research-dispatch` touched in this slice.
On return: run the parent-side acceptance gate (check-dispatch-artifact.sh with
--newer-than, then check-coverage-complete.sh on research-checklist.md), dispatch the
sibling verifier for verifier-owned criteria, apply project fit, then open round 2.

Dispatched mid-interview per user request before locking Q3+downstream:

1. What the canonical sources actually say about comments vs self-describing code:
   Clean Code ch.4 (Martin), Fowler Refactoring (comments as smell / "deodorant",
   refactor-first), Ousterhout APoSD (comments-are-underrated counterpoint) and the
   aposd-vs-clean-code debate transcript, Code Complete ch.32 (McConnell),
   Google eng-practices / style guidance.
2. One concern or two: is "delete comments that shouldn't exist" a separate discipline
   (own rubric) from "refactor code so the comment becomes unnecessary"?
3. The concrete transformation catalog that dissolves a comment (extract function,
   extract variable, rename, replace magic literal, guard clause, etc.).
4. Guidance specific to AI/agent-written code over-commenting, if any exists.

## Session-shorthand glossary

- *residue* — out-of-context comments (history/plan/conversation/ticket refs), the
  existing audit-comment-residue territory; distinct from *restating* comments.
- *what-comment / why-comment* — a comment describing what the code does (candidate
  for refactor-away) vs why it does it (keep).
