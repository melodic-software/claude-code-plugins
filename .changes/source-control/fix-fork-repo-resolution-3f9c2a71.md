---
bump: patch
---

### Fixed

- In a fork checkout, `pull-request` create, ready and evidence no longer leave the target repository to `gh`, which can pick upstream. Each phase resolves it once with the new `scripts/target-repo.sh`, prints it, and names it in every write. A fork checkout resolves to the fork even when `gh` records upstream as its default; remotes naming two unrelated repositories with no `gh repo set-default` recorded are refused with that fix.
- The create provider reference no longer says the worktree-anchored default-branch read returns the fork's branch: it returns the branch of whichever repository `gh` resolves, which can be upstream.
