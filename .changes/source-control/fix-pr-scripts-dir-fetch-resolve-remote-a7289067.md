---
bump: minor
---

### Added

- `fetch-annotations.sh`, `fetch-failed-logs.sh` and `fetch-all-pr-comments.sh` take `--dir <checkout>`, as `pr-worktree.sh`, `verify-gate.sh` and `confirm-verdict.sh` do, and resolve the repository there with `target-repo.sh` (which honors `GH_REPO`); `FETCH_ANNOT_REPO`, `FETCH_LOGS_REPO`, `FETCH_COMMENTS_OWNER` and `FETCH_COMMENTS_REPO` still win. `resolve-remote.sh` takes `--dir <checkout>` and reads that checkout's branch and remote config. Without `--dir`, each script uses the current directory as before.

### Fixed

- `/source-control:pull-request monitor` and `merge`: the log, annotation and comment fetches, the fix-commit check and the linked-worktree branch delete pass `--dir "<checkout>"` and run git with `-C "<checkout>"`, so a session whose shell is outside the target checkout reads and pushes to the right repository. The GitHub readiness reference names `<owner>/<repo>` on every `gh pr checks`, `gh run view` and `gh api` call instead of relying on the shell's directory or gh's `{owner}/{repo}` placeholders, and reads the head from `<checkout>`.
