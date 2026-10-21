---
bump: patch
---

### Fixed

- run a skill's script tests only inside the current repository

  Check 7 runs a skill's `scripts/*.test.sh` only when the test file is
  tracked in the git work tree the check was started from, root mode
  included, and an exported `GIT_DIR` or `GIT_WORK_TREE` does not change that
  answer. A test in another repository, in none, untracked under the
  invoker's work tree (a plugin copy under a home-directory repo), or checked
  from outside any repository is skipped with a note, so checking an
  installed plugin copy never executes its code.
