---
bump: minor
---

### Added

- The issue lane tidies its own diff before its review: after the checks pass, `simplify` and `code-tidying:dissolve-comments` run on the changed code and `docs-hygiene:audit-noise` and `ai-slop:audit` on the changed markdown, then the checks run again. A new `tidy` activity key lists the passes; the write runner allows exactly those skills, and a routing tool from the base skips them for a diff over 150 changed lines (provisional) or across more than one area. The passes may use a fifth of the run's turn cap, and a run with tidy passes is denied `git`.
