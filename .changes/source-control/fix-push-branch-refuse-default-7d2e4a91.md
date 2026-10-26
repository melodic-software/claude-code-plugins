---
bump: patch
---

### Fixed

- **pull-request:** `push-branch.sh` refuses, before any push, when the branch it would push (named, current, or the `--pr` head) is `main`, `master`, or the push remote's default branch as `git ls-remote --symref` reports it, and refuses when that read fails or names no default branch. A `--pr` head in a fork of the base repository is exempt, as in `lane-push.sh`: that push goes to the contributor's fork. Its new `--check` runs only that check. `create` pushes with `--dir <checkout>`, reads the PR's head branch from that checkout, and runs `--check` before opening the PR, so a working directory that reset to the main checkout no longer pushes `main` or opens a PR from it.
