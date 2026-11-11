---
bump: major
---

### Changed

- The `worktree-add-claim-gate` hook is renamed `worktree-add-claim` (`hooks/worktree-add-claim.sh`), and its option `worktree_add_claim_gate_enabled` is renamed `worktree_add_claim_enabled` (environment form `CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_ENABLED`). The hook never blocks a command: it claims the worktree a `git worktree add` created. A stored value under the old key is ignored and the new key starts at its default, `true`; if you had turned the hook off, set `worktree_add_claim_enabled` to `false` through `/plugin configure`.
