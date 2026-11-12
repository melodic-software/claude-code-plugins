---
bump: patch
---

### Changed

- audit-automation-gaps: a gotcha that a hook exiting 1 lets the action through unless it sets `"onFailure": "block"`.
- draft-auto-mode-rules: an action that must never happen is pointed at `permissions.deny` or a hook, with `hard_deny` kept as a second layer.
- Enforcement ladder copy updated to 2.1.1.
