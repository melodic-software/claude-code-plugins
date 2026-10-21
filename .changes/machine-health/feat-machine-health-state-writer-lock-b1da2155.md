---
bump: minor
---

### Added

- `/machine-health:setup apply` takes `revoke=<remediation>` to withdraw an approval and `unmute=<key>` to remove a finding mute under every check.
- One audit runs at a time per state folder: a second run reports one UNKNOWN `run-lock` result naming `state/run.lock` and writes nothing.
- A state folder under a cloud sync root (a OneDrive variable, or a reparse point carrying a cloud attribute) is detected: the run still runs the checks and writes the markdown report, adds one UNKNOWN `state-location` result, and creates or writes nothing under the state folder; a report folder under one only warns.

### Changed

- `approvals.json` and `mutes.json` are written only through `Set-ApprovalState`, which holds `state/approvals.lock`, validates the schema before writing, and replaces the file atomically; the one-time TODO.md migration uses the same replace. Hand edits of either file are unsupported while an audit or setup session runs.
