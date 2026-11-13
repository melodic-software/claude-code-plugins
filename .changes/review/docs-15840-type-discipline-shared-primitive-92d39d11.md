---
bump: patch
---

### Added

- The `code-reviewer` agent's copy of the shared type rules (`context/type-discipline.md`) gains a
  row: two values that share a primitive type and must never be swapped each get their own
  distinct nominal type, produced only by their parse.
