---
bump: patch
---

### Changed

- **The Bash gates spawn only for the commands they judge.** `pr-body-linkage-gate` now
  runs from three entries, `Bash(*pr create*)`, `Bash(*pr new*)` and `Bash(*pr edit*)`, in
  place of `Bash(*gh *)`, so it still sees `gh -R o/r pr create` and the `gh pr new` alias
  but no longer starts for every other `gh` call. `worktree-add-containment-gate` and
  `worktree-add-claim-gate` now run under `Bash(*worktree add*)` in place of
  `Bash(*worktree*)`, so `git worktree list` and paths that merely contain `worktree` no
  longer start them.
- **`/source-control:worktree create` skips `EnterWorktree` with no user present.** Outside
  `.claude/worktrees/`, the call asks for approval, which a headless run cannot give; the
  run works by explicit path with `git -C <literal path>` instead.
- **`/source-control:pull-request create` writes the PR body to a file.** The body is
  written with the Write tool, the pre-create gates read that file, and `gh pr create`
  gets `--body-file` (the REST fallback sends `-F body=@<file>`), so a long body no longer
  hits the Bash command length cap.
- **`/source-control:pull-request monitor` waits in the background.** The cloud baseline
  poll and the per-push CI wait run through the Monitor watch or a `run_in_background`
  poll, never a foreground `sleep` or `until` loop.
