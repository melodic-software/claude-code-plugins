---
bump: patch
---

### Fixed

- `worktree-claim.sh handover` releases the lock instead of passing it to the new session when the worktree's branch is `[gone]` upstream, matching `claim --all-unclaimed`. Before, each session handover re-locked every finished worktree it held, and the nightly reap skipped them while the new session ran: 302 landed worktrees on one host were held this way.
