---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/bugs.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/bugs:scan` dispatches no Step 4 gate and reports each candidate with `**Evidence**: unverified` and `verification: skipped (<level>)` in the run metadata; `--track` never files an unverified finding.
