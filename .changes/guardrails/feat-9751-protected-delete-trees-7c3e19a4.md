---
bump: minor
---

### Added

- `block-root-delete-target` refuses a recursive delete of a protected tree ahead of every root it allows, so even inside the working tree, a temp root, the session scratchpad or a listed root: a `.git` (and a glob straight inside one, `rm -rf .git/*`), a directory holding a `.git`, the git toplevel itself, every worktree root git has registered for the cwd's repository (read from its `worktrees/*/gitdir` files), anything under `~/.claude`, and Claude Code's temp tree outside this session's own scratchpad (another session's scratchpad, a project or session directory, the base). A directory holding one, or a glob whose matches reach one, is refused too, a glob matching dot names on the PowerShell tool or after `dotglob`; a path named under the toplevel, a worktree or `.git` is not, nor is the toplevel's bash `rm -rf *` ([#9751](https://github.com/melodic-software/claude-code-plugins/issues/9751)).
- `block_root_delete_target_protected_trees`: comma-separated absolute directories the guard protects the same way, read from the hook's own environment.

### Changed

- `rm -rf .` at the toplevel, a delete of a sibling worktree under a listed root, and a delete of a throwaway clone under temp, which the allowed roots used to pass, are now refused; the README's Option details list what stays allowed.
