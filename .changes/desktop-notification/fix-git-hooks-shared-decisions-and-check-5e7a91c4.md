---
bump: patch
---

### Fixed

- `setup check` keeps a missing `node` FAIL while the plugin's toggle is off: every hook row launches `node`, and the enabled-gate runs only after it starts.
