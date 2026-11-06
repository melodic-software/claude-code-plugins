---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/developer-experience.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/developer-experience.schema.json`. `/developer-experience:build-cli` review mode follows it: `strict` dispatches the fresh-context reviewer for every review, and `light` and `off` dispatch none, record `verification: skipped (<level>)`, and run the review in the main session with every gap labeled `unverified`.
