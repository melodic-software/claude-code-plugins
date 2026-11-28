---
bump: patch
---

### Changed

- The babysit-prs verdict reader shares a FAIL index's run artifacts across one pr-merge run's gate processes (`BABYSIT_RUN_CACHE`, section `run-artifacts`, for `run_cache.MAX_AGE`) once the set is final: it holds a FAIL, or it was read again after the run completed. A run still uploading is read by every process, as before. One Merge job made 40 `runs/{id}/artifacts` reads, none shared.
