---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: a pr-merge sweep's one whole-review request is now spent only by a pull request that passes the rate-limit and running-jobs limits. A candidate refused on a limit no longer leaves every later candidate in the sweep answered `sweep-limit`. The limits themselves and the one request per sweep are unchanged.
