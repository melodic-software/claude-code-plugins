---
bump: patch
---

### Fixed

- `/source-control:pull-request ready`: `verify-gate.sh` keeps its result under the repository's common git directory (`git rev-parse --git-common-dir`), shared by every worktree, instead of the per-checkout `git rev-parse --git-path`. A gate recorded with the shell in the main checkout for a pull request whose branch sits in a linked worktree, then checked from that worktree (or the reverse), no longer refuses the flip for a missing verify record. The record stays keyed by head commit.
