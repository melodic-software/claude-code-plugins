---
bump: patch
---

### Changed

- The shipped copy of the plugin-reconfiguration convention, `reference/plugin-reconfiguration.md`, now says the install `--config` rerun takes the scope `claude plugin list` reports for the plugin from any directory, the home directory included, and passes `user` only when that list shows one settings file as both `user` and `project`.
