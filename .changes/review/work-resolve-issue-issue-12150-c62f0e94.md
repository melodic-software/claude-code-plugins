---
bump: patch
---

### Added

- The `code-reviewer` agent reads a copy of the shared type rules
  (`context/type-discipline.md`) when a change declares or changes a type, and reports a departure
  from a rule as a suggestion. Its existing checklist items are unchanged.
