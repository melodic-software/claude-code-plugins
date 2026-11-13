---
bump: major
---

### Changed

- **Breaking:** `/planning:interview` now reads the `verification` level. Under the default `light` (and `off`) it dispatches no pre-round contradiction pass, no assumption sweep and no quote check: the round or restatement states `verification: skipped (<level>)` and the Step 2 exit box is ticked `SKIPPED: verification: skipped (<level>)`; a fact-settled sweep item without a quote check becomes a register row. Set `verification: standard` (or `verification_skills.interview`) in `docs/conventions/planning.yaml` on the default branch to keep the passes.
