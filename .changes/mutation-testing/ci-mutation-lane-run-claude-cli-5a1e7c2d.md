---
bump: minor
---

### Added

- `/mutation-testing:audit --phase generate|triage` runs one half of the audit, for a caller that executes the mutants itself in a process that holds no credential: generate returns each mutant's exact edit and runs no test, and triage classifies the executed survivors.
