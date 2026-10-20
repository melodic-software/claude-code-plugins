---
bump: minor
---

### Added

- The issue lane tidies its own diff before its review: after the checks pass, `code-tidying:dissolve-comments` runs on the changed code and `docs-hygiene:audit-noise` and `ai-slop:audit` on the changed markdown, then the checks run again. A new `tidy` activity key lists the passes; the write runner allows exactly those skills, each `<plugin>:<skill>` (a bare name is refused, since its rule would match a project skill the run writes), and a routing tool from the base skips them for a diff over 150 changed lines (provisional) or across more than one area. The passes may use a fifth of the run's turn cap, and a run with tidy passes is denied every rule the passes' `allowed-tools` grant (`git`, `echo`, `grep`, `head` and their scripts among them) and `/proc`, so the three plugin passes do not load until they need none of those.
