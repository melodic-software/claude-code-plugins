---
bump: patch
---

### Fixed

- In a fork checkout, `pull-request` create, ready and evidence no longer leave the target repository to `gh`, which can pick upstream. Each phase resolves it once with the new `scripts/target-repo.sh`, prints it, and names it in every write; a checkout whose remotes name two repositories with no `gh repo set-default` recorded is refused with that fix.
- The create provider reference no longer says the worktree-anchored default-branch read returns the fork's branch: it returns the branch of whichever repository `gh` resolves, which can be upstream.
