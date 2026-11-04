---
bump: patch
---

### Fixed

- `handoff` now names the save-point script by its path, `${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py`,
  so a run calls it directly instead of searching the plugin root for it.
