---
bump: patch
---

### Changed

- `/improvement:find` and `/improvement:improve` bodies are shorter, with every rule, gate and pointer kept. Eval passes on opus and sonnet showed no loss against the previous text.
- `/improvement:improve`'s description leads with what it produces (one small PR) and drops a sentence that repeated it; `/improvement:find`'s description opens with a noun phrase. Every quoted trigger phrase stays.

### Added

- Seven outcome eval cases: four for `/improvement:improve` (dry-run diff, no-argument ask, a target that already meets its standard, an instruction embedded in a target file) and three for `/improvement:find` (instrument-first, docs routed to their owning lane, an implement request handed to the pipeline). Fixtures and offline grader samples are included.
- Frozen trigger-probe sets `probes/find.json` and `probes/improve.json`, 18 queries each.

### Fixed

- The `already-built-disconnected-scan` cases check no-edit with must-not-call Write and Edit graders instead of a wording regex, require each fact and its qualifier to sit together, and grade the ranking order deterministically in place of an uncalibrated judge.
