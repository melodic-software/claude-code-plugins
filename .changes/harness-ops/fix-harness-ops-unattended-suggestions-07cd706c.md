---
bump: patch
---

### Fixed

- `/harness-ops:audit-install-state` and `/harness-ops:audit-skill-visibility` under `--unattended` omit the `/doctor` and `/skill-doctor` suggestions instead of recording them in the report, as `/harness-ops:audit-performance` already does: an unattended run neither suggests nor runs a command reserved for the person.
