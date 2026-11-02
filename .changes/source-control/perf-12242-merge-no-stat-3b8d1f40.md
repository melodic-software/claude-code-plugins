---
bump: patch
---

### Changed

- `push-branch.sh`'s stale-base merge and the `/source-control:pull-request ready` local-merge fallback run `git merge --no-stat`, so a merge returns its outcome line instead of a diffstat of every changed file.
