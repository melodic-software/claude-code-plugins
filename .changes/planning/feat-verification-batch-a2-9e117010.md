---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `<home>/planning.yaml`, read from the default branch by `lib/read-verification.sh`. `/planning:plan` Step 3 dispatches no plan-reviewer under `light` and `off`; `plan_stress_test` still decides whether the step runs.
