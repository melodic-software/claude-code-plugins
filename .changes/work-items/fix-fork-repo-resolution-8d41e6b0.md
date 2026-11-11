---
bump: patch
---

### Fixed

- `setup check` now reports when the remotes name more than one GitHub repository and no `gh repo set-default` is recorded, or the recorded default is not the fork, and prints the `gh repo set-default <owner>/<repo>` fix.
- The tracker contract and the GitHub adapter and the `morning-brief` script's comments describe `gh`'s real repository order (`GH_REPO`, the recorded default, then the first remote by name) instead of "the working directory's git remote".
- Plan comments, schedule reconciliation, label provisioning and the auto-merge disarm name the repository with `-R` instead of leaving it to `gh`.
