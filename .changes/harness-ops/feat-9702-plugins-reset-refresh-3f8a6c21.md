---
bump: minor
---

### Added

- `plugins` skill: `scripts/reset-refresh.sh`, an operator-run script for the user-scope plugin fleet. `preview` prints what `refresh` would move aside. `refresh` moves the marketplace clones and `cache/` into a run directory and re-fetches them through `claude plugin marketplace update` and `claude plugin install --scope user`. It exits non-zero when marketplaces, user installs or user `enabledPlugins` differ from their pre-run snapshots. It refuses to run under `CLAUDE_CODE_REMOTE` or while a `claude` process is running.
