---
bump: minor
---

### Added

- New denial, on by default: `block-main-checkout-edit` denies a Write, Edit or NotebookEdit to a file that is not git-ignored in a repository's main checkout while it is on the remote default branch (`origin/HEAD`). The reason gives the steps to make the edit in a worktree. Linked worktrees, other branches, a detached HEAD, git-ignored paths, paths outside a repository and repositories with no `origin/HEAD` pass. Writes made by shell commands are not seen. To turn it off, set `block_main_checkout_edit_enabled` to `false` (README, "How to set these").
