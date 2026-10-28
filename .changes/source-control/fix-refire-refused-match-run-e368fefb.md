---
bump: patch
---

### Changed

- The babysit merge floor holds `.github/actions/report-check-run/posting-run.mjs` as `gate`: the pr-merge re-fire script now loads it to find which run posted a check run.
