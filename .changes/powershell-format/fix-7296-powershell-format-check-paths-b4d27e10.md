---
bump: patch
---

### Fixed

- `setup check` tells the model to read each option value from the skill text, without restating how Claude Code renders it. Its Bash step cites the 3.2 floor from `lib/git-hooks/check-lib.sh` instead of the README.
- `setup check` names `prerequisites.json` by its path under the plugin root, so the model reads it instead of searching the plugin directory.
- `setup check` opens plugin files by the paths it names and never searches the plugin directory.
