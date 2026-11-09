---
bump: minor
---

### Added

- `/harness-config:audit-instructions` gains row I8-g, an advisory `behavioral` check that flags a standing "keep going", "loop until done" or "don't be lazy" line with no finish line or stop cases, which the Claude Code best-practices page says tends to cause over-work on current models. It never flags the finish-line and stop-case statement posture P6 asks of an autonomous component, a check, `/goal` or `Stop`-hook instruction, or a document about the pattern. The instruction scanner seeds candidates for it.
