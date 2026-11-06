---
bump: minor
---

### Changed

- `/knowledge:video-digest` checklist item 9.4, the vision fidelity spot-check, is dispatched to a fresh-context subagent instead of being run by the context that produced the slice.

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/knowledge.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/knowledge:video-digest` dispatches no spot-check, ticks 9.4 with `verification: skipped (<level>)` and reports the slice structural complete only, never vision-complete.
