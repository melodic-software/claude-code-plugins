---
bump: minor
---

### Changed

- `/planning:interview` hands decisions to `/architecture:record-decision` through a numbered round step, "Decision record" (step 8 of each frontier round, under `domain_docs`): each resolved decision about the system that weighed a real alternative is passed with its rationale and alternatives. The interview no longer carries its own copy of the ADR admission test; `record-decision` owns it. Without the `architecture` plugin the decision is recorded as an ADR candidate in its register row instead of a hand-written ADR.
- `/planning:plan close-out` hands ADR decisions to `/architecture:record-decision` and drops its copy of the admission test; without that plugin it lists ADR candidates in the PR body.
