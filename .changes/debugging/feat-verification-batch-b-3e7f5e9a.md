---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/debugging.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/debugging:debug` dispatches no fresh-context outcome verifier, records `verification: skipped (<level>)` and leaves the outcome unverified; the mechanical checks and the Phase 1 loop rerun still run.
