---
bump: minor
---

### Added

- `merge.refire-skip-branches` (default `[]`): head branches a workflow owns and rebuilds. pr-merge's re-fire step never comments on or pushes an empty commit to a pull request from one of them. This repository lists `release/plugins`, which `release-publish-plugins.yml` rebuilds. Skipping another owned branch takes only a config edit.

### Fixed

- pr-merge's re-fire step (`refire-refused.mjs`) now reports a pull request that changed since the listing, or whose branch a fresh read shows moved or deleted after a 409 or 422 on the ref update, as a `::warning::` for that pull request, and the other pull requests still re-fire. A pull request whose push has not landed an hour after its marker is a `::warning::` too, so a person looks. Before, one 422 on `release/plugins` failed the whole merge job (run 41065454536). Any other failure still fails the step: any error on the new commit, a 409 or 422 on a ref update whose branch is still at the head it was read at or whose tip cannot be read again, an auth refusal or server error on a write, a failed run, comment or blob read, a setup error, or a failed run listing. The step ends with a `refire-refused: outcome re-fired=N failed=N skipped-owned=N deferred=N` line in its log and step summary.
