---
bump: minor
---

### Changed

- Lane records resolve from `docs/conventions/ecosystems/<lane>.yaml` (and `<lane>.local.yaml`), falling back to the legacy `.claude/ecosystems/` file of a name absent there; with both present the new file wins and one warning names both. `/code-metrics:setup check` reports records at either location and warns on a legacy file the new home shadows.
