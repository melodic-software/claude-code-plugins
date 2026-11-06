---
bump: minor
---

### Added

- `compress_revert_below_pct` sets the percent below which `/docs-hygiene:compress` reverts a result with zero semantic loss. It defaults to 3, today's value, and `0` turns the auto-revert off. Set it per user in the plugin options or for a repository in `docs/conventions/docs-hygiene.yaml`; `--force` still bypasses it on one run.

### Changed

- The claim that `/caveman:caveman-compress` always removes articles now cites caveman's compress skill, with the date it was checked and what change would make it wrong.
