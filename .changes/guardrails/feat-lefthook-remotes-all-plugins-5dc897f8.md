---
bump: minor
---

### Added

- `apply install-git-hooks scope=shared` now commits a lefthook `remotes:` entry naming the
  marketplace's root `lefthook-remote.yml`, which carries every plugin's git hooks; a consumer
  whose entry names this plugin's own config still verifies `ok`.
- A failing remote job now prints the per-clone `lefthook-local.yml` skip for that job, except the
  secret and machine-path content scans, which still never suggest skipping them.
- A remote plan naming the root `lefthook-remote.yml` lists the plugins it turns on and reports
  a missing tool, decline or migration for each of their entries, and `verify` prints a
  `tool` line for each of their entries whose tool is missing.
