---
bump: patch
---

### Changed

- `/session-flow:audit-sessions` drift canaries are now validated against Claude Code 2.1.312. A collect and sweep over 2,387 sessions (2.1.280 through 2.1.312) found no `invariant:usage_regress`, `invariant:active_over_wall` or `invariant:stop_wait_over_sum` count, and `tokens.main` and `tokens.sub` report values on 2.1.296 transcripts.
