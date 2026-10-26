---
bump: patch
---

### Changed

- `pr-merge.yml` no longer wakes when `work-resolve-issue` finishes. That run could only disarm an armed pull request on a hold: an event run never arms (`enable-auto-merge.mjs` `READER_EVENTS`), and a pull request the issue lane just opened is not armed yet. The 15-minute schedule arms new lane pull requests as before, and `ci-status` still enforces every hold, on the pull request and in the merge queue. This removes about 1,000 run records and about 140 runner jobs a day.
