---
bump: minor
---

### Added

- `audit` proposes entries to prune, grouped by kind with a one-line reason: an implementation entry (a table, column, component, file or route), a term too general to carry project meaning, a canonical term no longer used, and a phrase one existing term already covers. A plain request such as "prune the glossary" or "the glossary feels bloated" routes to `audit`, which stays read-only.
- `curate` removes or merges entries a person accepted, one group at a time and only on a yes; unattended it writes nothing.
- Glossary contract: one counting method for every count `audit` and `curate` give (identifiers split at camelCase, PascalCase and snake_case boundaries, whole words, case-insensitive, with the number of files), and a rule that ADRs and docs use a term but never redefine it.

### Changed

- `curate`'s hand-off to `/docs-hygiene:rename-references` groups hits by layer: accepted ADR text takes the new term while ADR file names and numbers stay unchanged, and a stored database value is a decision, either a phased expand, migrate and contract migration or an explicit mapping, recorded with `/architecture:record-decision`.
