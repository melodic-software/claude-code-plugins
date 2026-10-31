---
bump: patch
---

### Fixed

- `/session-flow:audit-sessions` now counts a merge conflict only when a shell call runs `git merge`, `rebase`, `pull`, `cherry-pick`, `revert`, `am`, or `stash pop` or `apply`, and its result shows the conflict text. Before, any tool result with that text counted, including a `cat`, a `grep`, a Read or a CI log ([#11601](https://github.com/melodic-software/claude-code-plugins/issues/11601)).
