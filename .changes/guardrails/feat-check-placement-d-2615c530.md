---
bump: patch
---

### Fixed

- The guardrails dispatcher no longer lets a crash become an allow. A guard's `exit` ran the next
  guard on top of its own frames, so an attended `git reset --hard` followed by an over-budget git
  alias chain ran two alias walks on one stack. On Git Bash's 2 MB stack bash died, and the hook
  read as exit 0 with no output. Past 64 frames the rest of the chain now runs in a fresh process,
  and a rest of the chain that reports no verdict denies the call (it was exit 1, which Claude Code
  does not treat as a block). Once a guard has blocked, an abort in the dispatcher's own merge
  denies too; it used to exit 0 with a notice.
