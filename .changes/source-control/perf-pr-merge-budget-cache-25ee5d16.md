---
bump: patch
---

### Changed

- The pr-merge verdict reader accepts a run head an earlier run found on the default branch
  (`carried-on-branch` in the run cache) only for a FAIL's run, and a PASS never reuses a judgment
  made on a FAIL's path.
