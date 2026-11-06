---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/animation.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/animation.schema.json`. Under `light` and `off`, `/animation:produce` dispatches no fresh-context film reviewer at step 9, delivers with `verification: skipped (<level>)` and says the film was not independently reviewed; step 8's pack check still runs.
