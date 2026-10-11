---
bump: patch
---

### Fixed

- **`/performance:go-faster` records findings from a worktree-isolated session
  ([#6234](https://github.com/melodic-software/claude-code-plugins/issues/6234)).** `findings.py add`
  takes the findings as a `--json` argument (stdin still works when it is absent), and the sweeper
  passes them that way in one plain command per Bash call, never through a heredoc, which worktree
  isolation refused and left the run empty. The sweeper splits a large array across calls, returns
  `refused-by-guard` when an `add` or `finish` is refused, and the skill releases the lock and
  reports it. The skill also tells the main session not to enter or leave a worktree while a sweep
  runs.
