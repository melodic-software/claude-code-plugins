---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/codebase-health.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/codebase-health.schema.json`. `/codebase-health:audit` Phase 2 follows it: `strict` dispatches the separate false-positive validator even after an inline Phase 1, and `light` and `off` dispatch none, record `verification: skipped (<level>)` and report the findings `unverified`.
