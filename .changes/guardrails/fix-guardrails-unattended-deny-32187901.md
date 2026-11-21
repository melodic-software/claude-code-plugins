---
bump: patch
---

### Changed

- `settings-write-ask` now returns `deny` instead of `ask` when nobody can answer a prompt:
  `CLAUDE_CODE_SESSION_ATTENDED` is not `1` (as in `claude -p` and `claude --bg`), or
  `GUARDRAILS_SESSION_UNWATCHED` is `1`. This is the same test the blocking guards use, so an
  unattended lane never waits on this hook's prompt.
