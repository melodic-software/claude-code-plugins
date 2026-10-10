---
bump: patch
---

### Fixed

- `pull-request ready` pushes the pull request's head branch through `push-branch.sh --pr <number>`, so a session running in another worktree no longer pushes its own branch, prints "Everything up-to-date", and flips a PR whose pushed head lacks the base merge. `--pr` exits non-zero, without pushing, when the number is missing, the head branch has no local ref or starts with `-`, or the branch's push remote is not the PR's head repository.
