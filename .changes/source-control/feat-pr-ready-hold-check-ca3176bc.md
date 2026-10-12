---
bump: minor
---

### Changed

- `/source-control:pull-request ready` leaves a held or superseded draft in draft and reports why: a `do-not-merge` label, a body that says "do not merge" or has a `Hold:` line, a WIP title marker, or an already-closed linked issue. The check is `check-ready-holds.sh`, which fails closed when it cannot read the pull request.
