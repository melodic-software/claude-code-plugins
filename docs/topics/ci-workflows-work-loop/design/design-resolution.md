---
outcome: early-exit
date: 2026-07-23
topic: ci-workflows-work-loop (work-loop + babysit tracks)
---

# Design resolution — early exit

Tier assessment: deliverables are skill bodies (markdown), a repo-level convention doc + registry
row, one small hook/statusline plugin (`rate-limit-guard`), and a repo config file
(`.work-item-tracker.json`). No new programmatic types or package topology; the cross-plugin
contracts (escalation contract, capability-tier vocabulary, loop-layer invariants, guard
reader contract, `source-control.md` config keys) were resolved as interview threads across 6
rounds + 2 discipline sweeps and are locked in the two Briefs.

Design threads and their resolutions live in:

- `../PLAN.md` Brief (goals 1/1b/2/3/4, constraints, deferred questions with arbiters)
- `../babysit-PLAN.md` Brief (Q1–Q15 + HITL probe, placement reconciliation)
- Rationale ledgers: `../interview-checklist.md`, `../babysit-interview-checklist.md`

A separate `/planning:design` pass would re-derive contracts the operator already confirmed
(handoff marks them do-not-relitigate). The handoff's operator-confirmed next step routes
directly to `/planning:plan` over both Briefs — that instruction is the accepted skip.
