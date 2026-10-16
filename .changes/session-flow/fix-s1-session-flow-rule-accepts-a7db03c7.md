---
bump: patch
---

### Fixed

- `audit-sessions` friction scan: a tool call accepted by an allow rule (`reasonType: rule`) is no longer counted as `prompt-approved`; only a prompt the person answered is.
