---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/wizard.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/wizard.schema.json`. Under `light` and `off`, `/wizard:generate` Phase 3 skips the structure, count, `confirm` and banner items of its fresh-context read of the script and tells you at the approval gate `verification: skipped (<level>)`. The secrets checks run at every level: the library above the `STAGES` marker is diffed against `template.sh`, and the subagent still checks each value's destination and the `set_secret` / `set_var` names. `bash -n`, `shellcheck` and the approval gate still run.
