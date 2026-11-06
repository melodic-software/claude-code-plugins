---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/discovery.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/discovery:research`, `/discovery:explore` and `/discovery:trace-intent` dispatch no sibling verifier and write `verification: skipped (<level>)`, two new terminal values; under `strict`, research grades every row and claim and gives a FAIL row its rework round at every budget.
