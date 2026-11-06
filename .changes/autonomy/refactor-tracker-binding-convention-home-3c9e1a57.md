---
bump: patch
---

### Fixed

- The setup resolver's tracker probe reads the binding from the `tracker` mapping of `docs/conventions/work-items.yaml` first, and the legacy `.work-item-tracker.json` only when that file binds none, so a repository `/work-items:setup` migrated is no longer reported as having no tracker. The plugin now ships its own copy of the repository's YAML subset parser for that read.
