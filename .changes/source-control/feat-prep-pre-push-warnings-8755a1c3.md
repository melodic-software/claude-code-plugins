---
bump: minor
---

### Added

- `/source-control:pull-request prep` now runs `scripts/prep-warnings.sh` and lists two advisory warnings in its report before the first push: an existing `SKILL.md` or agent body that loses lines with no file added or changed under its eval home, and a changed path the unattended merge holds (`babysit_risk.HIGH_FLOOR` or the configured `merge.diff-check.denied-paths`, held for a person, or a plugin or marketplace manifest, which it compares base against head). The path rules are imported from `babysit_risk.py`, never restated. Neither warning blocks pull request creation. Found while landing #8714, where both cost extra push-and-review rounds.
