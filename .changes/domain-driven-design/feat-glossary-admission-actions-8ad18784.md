---
bump: minor
---

### Added

- Glossary contract: an optional `Actions:` line under an entity records the verb chosen for an operation on it when another verb was contested, the rejected one in parentheses (`Actions: submit (Avoid: raise)`). `lookup` returns it, resolves a rejected verb to its entry and tells its caller the verb is rejected only for that operation on that entity; `curate` and `audit` search for rejected verbs where they name that operation on that entity.

### Changed

- Glossary admission: everyday words used in their ordinary sense stay out; a term earns an entry only when it removes ambiguity in its context (a project-specific meaning, a clash between meanings, or a rejected synonym). `seed` leaves such words out and `audit` flags entries that do not pass.
