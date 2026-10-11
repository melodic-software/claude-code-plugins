---
bump: patch
---

### Fixed

- `/source-control:resolve-conflicts` now triggers when a stopped merge or rebase comes with a request to skip resolution by taking `--ours`/`--theirs` on every file or aborting, the case where its protections matter most (#7070).
