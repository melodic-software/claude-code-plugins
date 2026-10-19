---
bump: minor
---

### Added

- `/planning:design-handoff`: the gate requires a principles thread and a lifecycle-and-reversibility thread, each resolved, directional or tagged-deferred (a prototype names both as deferred); a design missing either fails.
- `/planning:plan`: Step 2's design-default checklist audits the same two threads and confirms the Brief carries the `Quality bar:` line a phase-boundary review rates at; the plan template says to tag `Review: code-design` on any phase that adds or changes a contract, type, module, or a fact or rule several files read, Markdown included, and maps each tag to its `/review:quality-gate` mode (`concurrency` to `slice concurrency`).
- `planning:plan-reviewer`: Design alignment flags a plan that places one fact or rule in several files or rebuilds what existing code already does, and a missing principle or reversibility thread.

### Fixed

- `/planning:design-handoff`: a failed gate opens its reply with the `Gate: FAIL` verdict and the coverage table before routing back to `/planning:design`, so the design round no longer replaces the verdict.
