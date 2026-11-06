---
bump: minor
---

### Changed

- `/event-storming:simulation` no longer scores the boards it just ran: every rubric score (Big Picture, Process Modeling, Design-Level and `--evaluate`) comes from a fresh-context subagent given the board export (or the structured-markdown artifact), the round transcripts and the rubric, per `simulation-evaluation.md` "How to Run an Evaluation", step 3.

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/event-storming.yaml`, read from the default branch by `lib/read-verification.sh` and validated by `schemas/event-storming.schema.json`. Under `light` and `off`, the skill dispatches no scorer, records `verification: skipped (<level>)`, leaves every criterion `unscored` and makes no version comparison.
