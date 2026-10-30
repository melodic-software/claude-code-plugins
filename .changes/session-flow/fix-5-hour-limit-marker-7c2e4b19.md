---
bump: patch
---

### Fixed

- The resume-eval harness stops at a usage limit again when Claude Code says "5-hour limit", the wording it uses since 2.1.312 in place of "session limit". Its limit marker now also matches a two-word limit name such as "Fable weekly limit".
