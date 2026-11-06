---
bump: patch
---

### Fixed

- gate clean's worktree hand-off on source-control

  The WORKTREE tier runs /source-control:worktree cleanup --dry-run only
  when the source-control plugin is installed; otherwise it names the
  worktree paths for the user.
