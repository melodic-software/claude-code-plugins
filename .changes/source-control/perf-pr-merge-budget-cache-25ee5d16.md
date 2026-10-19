---
bump: patch
---

### Changed

- The pr-merge verdict reader accepts what earlier runs read (`carried-run-record`,
  `carried-fail-head-ref` and `carried-on-branch` in the run cache) only on a FAIL's path and only
  where the value counts the FAIL; any other answer is read from GitHub, so a poisoned cache entry
  can add a refusal but never remove one. A PASS never reuses a judgment made on a FAIL's path.
