---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `<home>/code-tidying.yaml`, read from the default branch by `lib/read-verification.sh`. `/code-tidying:batch-simplify` skips the refutation verifier under `light` and `off`, and under `strict` runs it in every mode.
