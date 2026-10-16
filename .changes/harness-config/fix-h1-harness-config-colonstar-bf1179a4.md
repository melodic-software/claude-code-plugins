---
bump: patch
---

### Fixed

- `audit-permission-state` lint: `C6-colonStar` no longer fires on a rule body that starts with `*`, such as `PowerShell(*env:*lefthook*)`, where there is no command prefix and the colon is the literal the rule means to match.
