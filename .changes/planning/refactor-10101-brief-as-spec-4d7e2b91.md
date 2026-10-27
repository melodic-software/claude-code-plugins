---
bump: minor
---

### Changed

- The Brief is the spec, and each planning value has one owner. `/planning:interview`'s Brief template owns the Goal, the acceptance criteria and the deferred questions. `/planning:plan` writes no Goal of its own under `## Plan` and points at the Brief's. A minimal Brief written by plan now includes `### Acceptance criteria`. A plan with no Brief puts a one-line `Goal:` under its `No Brief: <reason>` line instead.
- `/planning:plan`'s Test strategy is the one place test boundaries are decided. `/planning:design`'s Test-seam posture thread sketches candidates for it and no longer asks the user to confirm them separately.
- PLAN.md has one `## Execution shape` section. It holds the routing table, the scope-fencing tables and the sequential fallback, so the `### Execution shape` subsection under `## Handoff to implementation` is gone. The `## Open questions` section is also gone: a question the plan raises is a Step 1 Open Decision, and a deferred question stays in the Brief's `### Deferred questions`, and Step 5 asks for a reply to each one still open as `USER-RESERVED`. Step 4.6 tags decisions in `## Execution shape` too. `/planning:design-handoff` sends uncovered dimensions to those Step 1 Open Decisions.
