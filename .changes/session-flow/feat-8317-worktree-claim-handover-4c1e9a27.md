---
bump: minor
---

### Added

- `/session-flow:handoff` and `/session-flow:continue-in-background` hand this session's worktree
  claims to the session that resumes the work. Each worktree whose lock names this session gets an
  Environment to re-establish entry with its path and the old session id, and the handover through
  source-control's `worktree-claim.sh handover` is the first remaining action (prompt-only: the
  first bullet), so the resuming session runs it before `check-enter`.
