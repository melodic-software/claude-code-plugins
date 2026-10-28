---
bump: patch
---

### Fixed

- The `/source-control:pull-request` ready and create references name `config-root.sh` by its `<plugin-root>/lib/` path, so an agent no longer runs a nonexistent `scripts/config-root.sh` (exit 127).
