---
bump: minor
---

### Added

- A `WorktreeRemove` hook (`hooks/worktree-remove-gate.sh`) reaps the project- and local-scope plugin install records of a worktree Claude Code removes itself (a `--worktree` session exit, `ExitWorktree`, a background-session delete, a `claude remote-control` cleanup) through `scripts/reap-project-plugin-records.sh`, then removes the worktree with plain `git worktree remove`, so those removals stop leaving stale records behind. It leaves the worktree on disk and exits non-zero for uncommitted or untracked changes, an operation in progress, submodules, a detached HEAD holding commits no ref holds, a lock whose reason names another session, or a reap that exits non-zero, and it keeps the branch. The hook needs the `claude` CLI on its `PATH`, now a declared prerequisite. Subagent and workflow-agent worktrees never reach the hook; `/source-control:worktree audit` Step 2b now says so, and `cleanup` still removes them.

### Changed

- A worktree Claude Code removes with uncommitted or untracked work now stays on disk: before this hook, Claude Code fell back to removing it with git, which discarded that work.
