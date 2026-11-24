---
bump: none
---

Removes the `codify-rules-ledger-accounts-for-every-rule` eval case: the eval sandbox mounts
`.git/worktrees` read-only, so `prove-check.sh` cannot create its worktrees there. No skill behavior
changes.
