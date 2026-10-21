---
bump: patch
---

### Fixed

- run a skill's script tests only inside the current repository

  Check 7 runs a skill's `scripts/*.test.sh` only when the git work tree the
  check was started from tracks the test file, or holds it untracked and not
  ignored in a skills root that already has a tracked file (a new skill not
  committed yet), root mode included; an exported `GIT_DIR` or
  `GIT_WORK_TREE` does not change that answer. A test in another
  repository, in none, ignored, tracked only by a nested repository, in a
  skills root with no tracked file (a plugin copy under a home-directory
  repo), or checked from outside any repository is skipped with a note, so
  checking an installed plugin copy never executes its code.
