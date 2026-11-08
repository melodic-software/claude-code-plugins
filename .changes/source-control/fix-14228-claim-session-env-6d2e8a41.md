---
bump: patch
---

### Fixed

- `worktree-claim.sh` reads the session id from `CLAUDE_CODE_SESSION_ID`, the variable Claude Code exports to Bash, when `--session-id` is absent, and keeps `CLAUDE_SESSION_ID` as a fallback. A bare `claim`, `check-enter` or `release` from a session now acts as that session, so its own claim no longer reads as foreign.
