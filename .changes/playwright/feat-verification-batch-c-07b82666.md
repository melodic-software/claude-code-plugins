---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/playwright.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/playwright.schema.json`. Under `light` and `off`, `/playwright:demo-video` dispatches no independent frame review at step 8, records `verification: skipped (<level>)`, reports the video as not independently reviewed, and posts nothing: the review is the frames' check for secrets and personal data that posting requires.
