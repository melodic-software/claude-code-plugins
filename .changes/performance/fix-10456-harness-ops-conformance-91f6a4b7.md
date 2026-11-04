---
bump: patch
---

### Fixed

- `/performance:go-faster` harness catalog: a timed-out PreToolUse hook blocks when its failure is
  set to block, and the skill listing's drop order follows ADR 0016 rather than the skills page.
  The Stop-hook timing pointer names the documented debug-log durations and why the transcript
  record stays.
