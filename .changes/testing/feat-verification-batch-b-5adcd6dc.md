---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/testing.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/testing:cleanup`'s Cannot-fail-only mode dispatches no step 2 skeptic, writes `verification: skipped (<level>)` as each row's skeptic verdict, clears no row and deletes nothing.
