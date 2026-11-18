---
bump: patch
---

### Changed

- **Restated upstream behavior cut to pointers in the README and the GitHub provider, stacked-PR and worktree-root references.** Passages that repeated Claude Code or GitHub docs now state this plugin's own rule with an anchored pointer, and drop their stamps except the async merge API's status list, which stays a stamped stored value. The rules cover which worktrees `worktree-remove-gate` leaves to `/source-control:worktree cleanup`, why you install Node.js yourself, treating GraphQL as unavailable behind the cloud GitHub proxy, marking a draft ready before a merge, the queue fields read back after `gh pr merge`, polling the `uuid` a 409 response returns, and how a stack layer merges. The `EnterWorktree(name:)` note now points to where the name form creates a worktree.
