---
bump: patch
---

### Fixed

- run a skill's script tests only inside the current repository

  Check 7 runs a skill's `scripts/*.test.sh` only when the skill sits in the
  git work tree the check was started from, root mode included. A skill in
  another repository, in none, or checked from outside any repository has
  its script tests skipped with a note, so checking an installed plugin copy
  never executes its code.
