---
bump: minor
---

### Added

- A fifth canonical role, `session-owned` (default label `session-owned`, remapped through `config.role_labels["session-owned"]`): a local Claude Code session owns the item and does it itself. `list-frontier --autonomous` excludes an item carrying it, so `/work-items:work-loop` never admits one; the interactive frontier keeps it for the owning session. The binding exports it as `WIT_SESSION_OWNED_LABEL`, and the label taxonomy, tracker seam, schema and CONTRACT name it.
