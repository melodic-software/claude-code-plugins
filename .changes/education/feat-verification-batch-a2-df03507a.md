---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `<home>/education.yaml`, read from the default branch by `lib/read-verification.sh`. `/education:quiz-me` skips the fresh-context answer-key pass under `light` and `off` and marks the key `verification: skipped (<level>)`.
