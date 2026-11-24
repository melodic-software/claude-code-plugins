---
bump: minor
---

### Changed

- The hosted review callers' defer horizon, `defer-run-minutes-review`, is 8 minutes instead of 11, so a first-attempt review defers only while the GITHUB_TOKEN window is projected to run short within 8 minutes. Replayed over the 48 busiest windows of 2026-11-22 to 2026-11-24, it defers fewer reviews and leaves no window newly at or under `stop-floor`. pr-merge and check-intent keep their horizons.
