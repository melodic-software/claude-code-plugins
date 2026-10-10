---
bump: patch
---

### Fixed

- **`/harness-ops:plugins` sync no longer says `install_new: all` reinstalls a plugin on every sync.** An installed plugin is not reinstalled; one you uninstall is, because `claude plugin uninstall` removes its install record and its `enabledPlugins` key together. The `Installed:` row now says so and tells the user to disable a plugin with `claude plugin disable <id> -s user` instead of uninstalling it, and audit's `Would install:` row gives the same warning and remedy in the future tense. When every plugin the run installed is already not enabled, the row drops the disable instruction and says leaving them installed keeps them off unless a project or local setting enables them. The install-enable spoke's caveat gives the same remedy in place of "uninstall AND disable" (#6183).
