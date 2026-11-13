---
bump: minor
---

### Added

- `branch-update-signals.sh` takes `--dir <checkout>`, as `fetch-all-pr-comments.sh` and `resolve-remote.sh` do: every git read runs in that checkout, and the repository is resolved there with `target-repo.sh` (which honors `GH_REPO`); `--repo` still wins. Without `--dir`, the script reads the current directory and gh's `{owner}/{repo}` placeholders as before.

### Fixed

- `/source-control:pull-request ready` 2.5.2 and the shared update sequence name `<branch-checkout>`, the path of the checkout holding the branch (for a PR, the worktree `pr-worktree.sh` prints), where they said "from the PR's checkout": `push-branch.sh`, `resolve-remote.sh` and `branch-update-signals.sh` get `--dir "<branch-checkout>"`, and the base fetch and merge, the fast-forward after the forge's update and the signed-head read run with `git -C "<branch-checkout>"`, so a session whose shell is outside the PR's checkout can run the step.
