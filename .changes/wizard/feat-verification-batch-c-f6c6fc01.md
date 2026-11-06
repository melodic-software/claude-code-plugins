---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/wizard.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/wizard.schema.json`. Under `light` and `off`, `/wizard:generate` dispatches no fresh-context read of the script in Phase 3 and tells you at the approval gate `verification: skipped (<level>)`; `bash -n`, `shellcheck` and the approval gate still run.
