---
bump: patch
---

### Fixed

- `/source-control:pull-request ready` runs its verify gate against the pull request's worktree and records that worktree's HEAD, whichever checkout the shell sits in. A session in the main checkout running `ready <pr>` for a PR built in another worktree used to run the main checkout's `scripts/check-affected.sh` over the main checkout. The new `scripts/pr-worktree.sh --pr <n>` prints the worktree that has the PR's head branch checked out with the PR's head commit in its history, and exits 2 when none has (a fork's `main` beside this repository's main checkout included), so nothing is recorded and the flip refuses. The flip's `HEAD_SHA` comes from the same worktree.
