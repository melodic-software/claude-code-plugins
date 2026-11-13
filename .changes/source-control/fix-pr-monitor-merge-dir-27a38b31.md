---
bump: minor
---

### Added

- `confirm-verdict.sh` takes `--dir <checkout>`, as `pr-worktree.sh` and `verify-gate.sh` do, and finds the common git directory there (`CONFIRM_VERDICT_DIR` still wins). The `ready` report (2.5.6) passes `--dir "$PR_TREE"` and the `evidence` action passes `--dir "<checkout>"`. Without `--dir`, the script uses the current directory as before.

### Fixed

- `/source-control:pull-request monitor` and `merge`: the PR identity block and the Monitor poll script take the repository from `target-repo.sh --dir "<checkout>"` instead of `gh repo view`, and read the PR number with `-R`, so a watch armed from a shell outside the target checkout polls the right repository. Every other `gh` command in the GitHub monitor and merge references names `<owner>/<repo>` instead of relying on the shell's directory or gh's `{owner}/{repo}` placeholders, and the merge-after-AI-review script resolves its repository the same way.
