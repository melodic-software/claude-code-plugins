---
bump: patch
---

### Changed

- The shipped copy of the plugin-reconfiguration convention, `reference/plugin-reconfiguration.md`, now says the install `--config` rerun takes the scope `claude plugin list` reports for the plugin, with a `project` or `local` rerun run from the project that install lives in, and passes `user` only when the working directory is the home directory and the list labels the plugin both `user` and `project`.
