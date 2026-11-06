---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/playwright.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/playwright.schema.json`. Under `light` and `off`, `/playwright:demo-video` step 8 skips the quality part of the independent frame review, records `verification: skipped (<level>)` and reports the video as not independently judged for quality. The fresh-context check for secrets and personal data in the frames still runs at every level and still gates posting.
