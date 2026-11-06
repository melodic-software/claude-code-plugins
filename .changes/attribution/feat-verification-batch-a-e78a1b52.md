---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `<home>/attribution.yaml`, read from the default branch by `lib/read-verification.sh`. `/attribution:audit` forces the review pass under `strict`, and under `light` and `off` skips the review pass, the refutation pass and the fix flow semantic-diff check; a skipped refutation never makes a finding relay-eligible.
