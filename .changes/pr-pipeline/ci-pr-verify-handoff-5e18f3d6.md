---
bump: minor
---

### Changed

- pr-verify hands the judgment to the subscription job on run-claude-cli's `handoff` output instead of the `credit-stop` class, so a key the API refuses with status 401 or 402 (class `auth`) also falls back; a 403 still fails the key job. The key-leg warning says whether to replace the key or rotate one in. The subscription job's lane record is plain `pr-verify`, with the reason in `fallback-reason` (`credit-stop`, `auth` or `no-key`). Every ci-workflows action pr-verify uses is pinned to v0.58.0, whose run-claude-cli installs the latest Claude Code release by default.
