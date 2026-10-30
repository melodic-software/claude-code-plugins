---
bump: minor
---

### Added

- `merge.refire-skip-branches` (default `[]`): head branches a workflow owns and rebuilds. pr-merge's re-fire step never comments on or pushes an empty commit to a pull request from one of them. This repository lists `release/plugins`, which `release-publish-plugins.yml` rebuilds. Skipping another owned branch takes only a config edit.

### Fixed

- pr-merge's re-fire step (`refire-refused.mjs`) now handles each failed run read, marker comment or ref update as a `::warning::` for that pull request, and the other pull requests still re-fire. Before, one 422 on `release/plugins` failed the whole merge job (run 41065454536). The step ends with a `refire-refused: outcome re-fired=N failed=N skipped-owned=N deferred=N` line in its log and step summary. It still fails on setup errors (an unreadable resolved config, a tag named main, main's tip) and when a lane's run listing fails.
