---
bump: patch
---

### Changed

- `continue-in-background`: the launch report now says a denied action does not stop the
  launched session and that the denial is in its transcript and `claude logs`, reaching the final
  hand-off only when the task reports it. The statement rests on a new probe record,
  `reference/denial-probe.md` (Claude Code 2.1.312, 2026-10-28). Whether a session stops on a
  prompt after auto mode falls back on repeated denials stays unverified.
