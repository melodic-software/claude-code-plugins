---
bump: patch
---

### Fixed

- The `setup` skill's git-hook decisions reference no longer restates when husky sets `core.hooksPath`; the `husky-install` row keeps its action: tell the user to run the project's install.
- `setup check` no longer downgrades a tool the git pre-commit entry needs to INFO while the plugin's toggle is off and that entry is installed: the entry runs at commit outside Claude Code and reads no toggle, so the tool keeps the grade it gets with the toggle on.
- `setup check` keeps a missing `node` FAIL while the plugin's toggle is off: every hook row launches `node`, and the enabled-gate runs only after it starts.
