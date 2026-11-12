---
bump: patch
---

### Changed

- audit-automation-gaps: a gotcha that a hook refusing by exit 1 is not counted as a gate until its event's exit-code semantics are read live.
- draft-auto-mode-rules: an action that must never happen is pointed at `permissions.deny` or a hook, with `hard_deny` kept as a second layer.
- Enforcement ladder copy updated to 2.1.1.
