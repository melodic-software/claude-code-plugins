---
bump: patch
---

### Fixed

- pr-merge no longer escalates a pull request to a human as `verify:earlier-fail` when a verify record, run time or diff could not be read (a rate limit, say): it refuses `verify:unreadable`, which the next run re-derives (#9063).
