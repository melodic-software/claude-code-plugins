---
bump: patch
---

### Fixed

- `setup check` tells the model to read each option value from the skill text, without restating how Claude Code renders it. Its Bash step cites the 3.2 floor from `hooks/hook-utils.sh` instead of the README.
- `setup check` opens plugin files by the paths it names and never searches the plugin directory.
