# /planning:interview Checklist — plugin-marketplace-code-clarity

Topic: a potential new skill (or extension of existing skills) covering comment removal
in favor of self-describing, expressive code, in this plugin marketplace.

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect — routed to Q&A (real design decisions with no codebase answer)
- [x] Step 2: Drive the frontier-rounds loop (4 rounds + research + audit-answers validation)
- [x] Step 3: Stop condition — register gate clean; user locked the contract ("I'll lock it")
- [ ] Step 4: Persist the contract (Brief → docs/topics/plugin-marketplace-code-clarity/PLAN.md)
- [ ] Step 5: Hand off (naming pass, then /planning:plan or direct implementation)

- [x] Plugin home + name — home: code-tidying; name via naming pass (Q16, user picks)

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
- Q3 | answered | round 3 | Doctrine — where on the Ousterhout ⇄ Clean Code spectrum; which comments survive? | Resolved via research + Q4: the canon's agreed floor (delete class A; refactor-then-delete class B) plus the Q4 terse earn-its-keep rule for class C. Verified research artifact: .work/plugin-marketplace-code-clarity/RESEARCH.md.
- Q4 | answered | round 3 | Class-C width: which comments survive? | Earn-its-keep test, final: a comment survives only if (a) it carries information code cannot express, (b) it is load-bearing at the point of reading (future editor risks a bug/misuse without it), and (c) it is terse (1-2 lines). Lengthy why-comment treatment: extract durable constraint to a one-liner, route narrative to the commit message, delete the rest. Justification-of-choices always routes out of code (commit/PR/ADR). Q3 resolves with this: the spectrum question dissolves into the agreed floor + this class-C rule.
- Q5 | answered | round 2 | Should the skill flag MISSING comments? | No. Treats existing comments/expressiveness only.
- Q6 | answered | round 2 | One skill vs two components? | One skill hosting the explicit three-way triage (delete / refactor-then-delete / keep).
- Q7 | answered | round 2 | Mode: applies edits vs read-only? | Applies edits, safety gradient: class-A deletes near-mechanical; class-B refactors only with a test/lint safety net, else proposed not applied.
- Q8 | answered | round 2 | Default run scope? | Uncommitted/diff-scoped default; explicit file/dir target optional.
- Q9 | answered | round 2 | Naming approach? | Run /naming:name-it-better once scope locks; user criteria (semantically correct, explicit over implicit) as declared conventions.
- Q10 | answered | round 3 | Doc-comment fence? | Public-API doc comments (docstrings, C# XML docs, JSDoc on exported surfaces) are EXEMPT — never touched. Private/internal doc comments get the same three-way triage as regular comments.
- Q11 | answered | round 3 | Ecosystem exclusions? | Code files only, language-agnostic; markdown excluded (docs-hygiene territory, same fence as audit-comment-residue). No per-language exclusions — the Q7 safety gradient (class-B proposed-not-applied without a test net) covers fragile ecosystems.

- Q12 | answered | round 4 (audit-answers) | A3 repairs | ACCEPTED, all four: (a) terse is a default posture, not a hard line cap; (b) sanctioned exceptions never touched: legal/license headers, machine-read directives (pragmas, lint directives, region markers), TODO(#issue), opt-out marker; (c) justification DEFAULTS to routing out of code — a terse in-code why is legitimate; (d) stripped narrative is staged as a proposed commit-message block (or /source-control:commit handoff) before deletion is final.
- Q13 | answered | round 4 (audit-answers) | A5 repair | ACCEPTED: tests gate class-B application (lint supplementary); the skill must discover a runnable test command covering the touched code, else class B is proposed, never applied.
- Q14 | answered | round 4 (audit-answers) | A8 internal half | Explicit choice: private/internal doc comments are triaged under the repaired class C (Martin pole, chosen deliberately, not as a side effect).
- Q15 | answered | round 4 (audit-answers) | A9 repair | ACCEPTED: adopt the plugin's standard path-exclusion tier mirroring tidy's exclusions.md (.claude/settings*, hooks, .github/workflows/**, lint/enforcement config).
- Q16 | deferred | naming pass | Final skill name | USER-RESERVED — being resolved via /naming:name-it-better; human picks from the shortlist; criteria: semantically correct, explicit over implicit.

## Answer-validation merge (2026-08-17, two fresh validators)

CONFIRMED by both: A1, A2 (+authoring note: description needs explicit Skip-when fences),
A4, A6 (+note: auto-committed diffs covered by explicit-path mode), A7 (+note: user naming
criteria enter name-it-better as a reweight). Challenged/reclassified → Q12-Q15 above.
Dependency notes: A1 holds only with A8's public fence intact; A3's routing defect is a
consequence of the edits-but-never-commits run shape; A9's fix is path-tier, not language.

## Resolved (round 3, 2026-08-17)

Q4, Q10, Q11 locked per user ("go with the recommendations"; Q4 confirmed with the
terse earn-its-keep refinement). Frontier empty pending answer validation
(/planning:audit-answers per user's verifier-agents request) and the confirmation gate.

## Resolved (round 2, 2026-08-17)

Q5–Q9 locked per user ("go with your recommendations"; Q5 explicit No). Q4 held open on
user nuance: comments must not carry lengthy justification; rationale belongs to
context/git history; terse constraint comments acceptable. Round 3 asks Q4-revised + Q10 + Q11.

## Decision tree (`me` mode)

- [x] Motivation / primary use case (Q1) — agent-written code, enforcement-on-invocation
- [x] Deliverable shape (Q2) — one new code-tidying skill hosting the three-way triage (Q6)
- [x] Comment doctrine + aggressiveness (Q3/Q4) — agreed floor; class C = terse earn-its-keep
- [x] Mode (Q7) — applies edits; class-B safety gradient (test net or propose-only)
- [x] Trigger surface (Q8) — on-demand, diff-scoped default, optional explicit target
- [ ] Plugin home + name — home: code-tidying; NAME pending /naming:name-it-better run (Q9; criteria: semantically correct, explicit over implicit)
- [x] Overlap fences (Q10/Q11 + project-fit) — audit-comment-residue keeps residue classification; tidy keeps lane machinery; public-API docs exempt; markdown excluded
- [x] Ecosystem scope (Q11) — language-agnostic code files; missing-comment flagging out (Q5)

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
