---
bump: minor
---

### Added

- `block-root-delete-target` judges `git worktree remove --force` (or `-f`) the way it judges a recursive `rm`. The `<worktree>` operand is a target, and so is every registered worktree whose path ends in it, since git looks a worktree up by its trailing path components first. So `git worktree remove --force /`, one aimed at `$HOME` and one outside the allowed roots are refused, and one strictly inside the git toplevel, the scratchpad or an allowed root passes. A registered worktree root stays protected unless it is not the git toplevel and sits strictly under a temp root, the scratchpad or an allowed root.
