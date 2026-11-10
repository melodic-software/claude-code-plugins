---
bump: patch
---

### Changed

- The glossary contract keeps business rules out of entries: an entry says what a concept is, the rule lives in code and a test that names it, and the rule's reason goes in an ADR when it passes `/architecture:record-decision`'s admission test. `audit` reports a rule found in a definition.
- `/domain-driven-design:ubiquitous-language` names `/architecture:record-decision` for decisions about why the system is built a certain way.
