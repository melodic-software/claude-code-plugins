---
bump: patch
---

### Fixed

- `/source-control:setup apply` resolves the repository root in its own Bash calls and writes it as a literal `<project root>` in its `layer=team` and `layer=local` snippets, so a worktree-isolated session can run them as written.
- The `layer=team` snippet's `.gitignore` probe runs `git -C "$REPO_ROOT" check-ignore`, as the snippet's other git commands do. Before, it ran from the current directory, so a session outside the repository's working tree hit a git error that the probe read as "no match", and the snippet then reported success.
