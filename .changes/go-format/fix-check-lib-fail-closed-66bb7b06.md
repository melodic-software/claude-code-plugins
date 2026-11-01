---
bump: patch
---

### Fixed

- The shared git hook library this plugin carries now fails a hook when git or awk fails while it lists the changed lines or filters findings to them. This plugin's hook does not use that scan, so its behavior is unchanged.
