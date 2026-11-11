---
bump: patch
---

### Fixed

- The `setup` skill's git-hook decisions reference no longer restates when husky sets `core.hooksPath`; the `husky-install` row keeps its action: tell the user to run the project's install.
- `setup check` keeps a missing `node` FAIL while the plugin's toggle is off: every hook row launches `node`, and the enabled-gate runs only after it starts.
