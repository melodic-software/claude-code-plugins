---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `<home>/ai-slop.yaml`, read from the default branch by `lib/read-verification.sh`. The `/ai-slop:audit` fix flow skips its semantic-diff subagent under `light` and `off`.
