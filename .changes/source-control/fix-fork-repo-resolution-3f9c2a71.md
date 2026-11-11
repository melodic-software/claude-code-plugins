---
bump: patch
---

### Fixed

- In a fork checkout, `pull-request` create, ready and evidence no longer leave the target repository to `gh`, which can pick upstream. Each phase resolves it once with the new `scripts/target-repo.sh`, prints it, and names it in every write. A fork checkout resolves to the fork even when `gh` records upstream as its default, but only a fork you can push to, so a maintainer who adds a contributor's fork as a remote keeps writing to the recorded default; a failed repository read stops the phase instead of falling back to upstream. Remotes naming two unrelated repositories with no `gh repo set-default` recorded are refused with that fix.
- The create provider reference no longer says the worktree-anchored default-branch read returns the fork's branch: it returns the branch of whichever repository `gh` resolves, which can be upstream.
