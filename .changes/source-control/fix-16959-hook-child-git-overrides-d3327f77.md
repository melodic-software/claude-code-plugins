---
bump: patch
---

### Security

- The worktree-add containment gate's worktree-root lookups (`config --get-all`, `rev-parse --git-dir` in `worktree-root-resolve.sh`) run through `hook::git_untrusted`, with the repository's `core.fsmonitor`, git hooks and pager turned off, as the gate's other git calls already do.
