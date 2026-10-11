---
bump: patch
---

### Changed

- `/session-flow:clean-stop` no longer names `gh`: a branch with no issue in its name gets its PR from the forge's own tooling, and `/source-control:pull-request create` is used when it can run unattended with the linkage decision passed in.
