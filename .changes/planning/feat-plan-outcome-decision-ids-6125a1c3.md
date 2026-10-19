---
bump: minor
---

### Added

- `check-plan-outcome.sh` maps each decision tag to its table row by id: a tag written `[EXEC-SHAPE D4]` or `[FALLBACK D7]` and a row starting its Decision column with the same id. The `decisions` criterion fails a tag id with no row and a row id no tag cites, naming each id, and prints `mapped=<n>` on pass. A bare tag with no id still passes, with a `warning=bare-tag` line. The plan template and `tag-decisions.md` show the id form.
