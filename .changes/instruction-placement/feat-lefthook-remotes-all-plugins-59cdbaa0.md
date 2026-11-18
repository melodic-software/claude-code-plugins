---
bump: minor
---

### Added

- The git-hook entries ship as a lefthook remote (`git-hooks/lefthook-remote.yml`), and
  `apply install-git-hooks scope=shared` prefers it: one `remotes:` entry naming the
  marketplace's root `lefthook-remote.yml` runs them from main, with nothing copied.
- The session-start drift check counts an entry installed through that remote as `ok`.
- A failing remote job prints the per-clone `lefthook-local.yml` skip for that job.
- A remote plan naming the root `lefthook-remote.yml` lists the plugins it turns on and reports
  a missing tool, decline or migration for each of their entries, and `verify` prints a
  `tool` line for each of their entries whose tool is missing.
