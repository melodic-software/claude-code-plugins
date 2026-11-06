---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/writing.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/writing.schema.json`. `/writing:be-concise` follows it for its fresh-context semantic diff: `strict` runs the diff on every rewrite whatever its size, and `light` and `off` run none, record `verification: skipped (<level>)` and say the meaning was not independently checked.
