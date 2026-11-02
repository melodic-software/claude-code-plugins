---
bump: patch
---

### Fixed

- `guard_launch_monitor.py` now uses its `.warned` and `.cursor` files in the shared tmp fallback directory only when that directory is not a symlink and the current user owns it. Before, another local user could create the directory first and plant a `.warned` file there to silence the warning ([#7373](https://github.com/melodic-software/claude-code-plugins/issues/7373)).
