---
bump: minor
---

### Added

- `/planning:interview` page surface round tooling (#6050): a yes/no question flagged `"binary": true` carries exactly one alternative, refused when it repeats or contains the recommendation; `add-round --check` runs every refusal and warning and writes nothing; `add-round --sync-ledger '<ledger>'` posts the round and syncs the register in one command, refusing a ledger without exactly one register heading before anything is written; and a question added after a later round was posted records `addedInRound`, shown on the page as `Added in round N` and in the register's round cell, which `import-ledger` reads back. `context/surface.md` documents the round fields, the one-command round step with literal single-quoted paths, and editing a round file with the Write or Edit tool before `add-round` or `revise` ops after it.

### Fixed

- `/planning:interview` page surface (#6050): `add-round` names the question and the missing field when it refuses one without `id`, `short` or `title`.
