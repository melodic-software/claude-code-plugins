---
bump: patch
---

### Changed

- `stale-path-verify` checks cited paths against its deleted-paths cache with one `awk` call

  Each run used to load every path in the cache into a bash array. Now the guard first collects
  the cited paths that are missing from the working tree. One `awk` call then checks the cache's
  shape (the HEAD sha, `ok`, the `end <count>` sentinel, and no second sentinel) and prints the
  cited paths the cache lists. A cache that fails the shape check is rebuilt from history, as
  before.
