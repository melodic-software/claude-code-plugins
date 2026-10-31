---
bump: minor
---

### Added

- `/source-control:babysit-prs` takes an optional leading `unattended` argument. With it, the run records the `/autofix-pr` offer in its output instead of asking; without it, the run asks.
- `/source-control:pull-request` lists `--unattended` in its argument hint. With it, on any action, the run records the watch-route recommendation and the `/autofix-pr` prompt in its output instead of asking; without it, the run asks.

### Changed

- `/source-control:pull-request`'s argument hint shortens its action set with `…` to stay within the 100-character budget; the Arguments table keeps the full set.
