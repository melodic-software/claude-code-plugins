---
bump: patch
---

### Fixed

- In a fork checkout, `pull-request` create, ready and evidence no longer leave the target repository to `gh`, which can pick upstream. Each phase resolves it once with the new `scripts/target-repo.sh`, prints it, and names it in every write. Ready and create export it as `GH_REPO` once it is resolved, so their later reads, and the scripts they run, target it too; evidence resolves it first and names it on every read. `branch-update-signals.sh` without `--repo` now reads the repository through `gh api`, which follows `GH_REPO`, instead of `gh repo view`, which ignores it. A fork checkout resolves to the fork even when `gh` records upstream as its default, but only a fork you can push to, so a maintainer who adds a contributor's fork as a remote keeps writing to the recorded default; a failed repository read stops the phase instead of falling back to upstream. Remotes naming two or more GitHub repositories, none a fork of another that you can push to, with no `gh repo set-default` recorded, are refused with that fix.
- The create provider reference no longer says the worktree-anchored default-branch read returns the fork's branch: it returns the branch of whichever repository `gh` resolves, which can be upstream.
