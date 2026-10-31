---
bump: minor
---

### Added

- `worktree-claim.sh handover <path> --session-id <old> --to <new>` moves a worktree claim to the
  session that resumes a handoff. It re-locks only when the lock reason names `<old>`, writes a
  reason naming `<new>` that keeps the creator script the old reason named, and exits 4 when the
  lock names any other session. `/source-control:worktree` documents it next to the claim gate,
  so a session resumed after `/clear` no longer meets `FOREIGN CLAIM` on its own lane's worktree.
