---
bump: minor
---

### Fixed

- `/review:ratchet`: the vendored `suppression-scan.py` takes `--exclude <glob>` (repeatable) and `--exclude-from <file>`, so a suppression counter can skip the paths the team's audit scope excludes and stay equal to the audit report. Without them the count is unchanged.
