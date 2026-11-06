---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/mutation-testing.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/mutation-testing:audit` dispatches no Phase 4 triage subagent and reports every survivor unclassified with the reason `verification: skipped (<level>)`.
