---
bump: patch
---

### Changed

- The babysit-prs verdict reader shares a FAIL index's run artifacts across one pr-merge run's gate processes (`BABYSIT_RUN_CACHE`, section `run-artifacts`, for `run_cache.MAX_AGE`) when the set holds a FAIL, noting when it was read. A set with no FAIL is read by every process, since a re-run keeps the run's id. One Merge job made 40 `runs/{id}/artifacts` reads, none shared.
