---
bump: minor
---

### Added

- `/session-flow:recommend-skills` takes a free-text question and answers with one skill from the resolved catalog, its arguments and one example prompt (goal, pass/fail check, proof wanted, known facts, constraints; no method and no guessed cause). A run with no question, or a topic slug, still renders the full menu.

### Changed

- `/session-flow:workflow` step 5 and `/session-flow:orchestrate` keep a task-list entry that will not be done listed as `skip: <reason>` instead of dropping it.
