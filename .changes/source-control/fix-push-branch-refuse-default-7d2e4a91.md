---
bump: patch
---

### Fixed

- **pull-request:** `push-branch.sh` refuses, before any push, when the branch it would push (named, current, or the `--pr` head) is the push remote's default branch, read from `<remote>/HEAD`. With that unset it refuses `main` and `master` and says so. `create` pushes with `--dir <checkout>`, reads the PR's head branch from that checkout, and refuses to open a PR whose head is the remote's default branch, so a working directory that reset to the main checkout no longer pushes `main` or opens a PR from it.
