---
bump: minor
---

### Changed

- **Breaking:** `/domain-driven-design:curate-language` is renamed `/domain-driven-design:ubiquitous-language`. Invoke the new name; the settings `glossary_file` and `glossary_map_file` and their file `docs/conventions/domain-driven-design.yaml` are unchanged.
- The skill now has five actions: `locate` (find the glossary, searching the whole repository so a `docs/glossary.md` is found), `lookup` (the read-only path other skills use), `seed` (propose a first glossary from code and docs, a person accepting each term), `curate` (the previous maintenance workflow) and `audit` (check entries and find rejected words in code, copy and error messages, report only).
- Glossary contract: a header sentence says what `Avoid:` means; an entity's states are listed under it, with a state getting its own entry only when it is used as a noun with rules of its own; an optional `Shown to users as:` line records deliberate screen wording. The map file is called the glossary index. Missing bounded contexts route to `/event-storming:simulation`.
- After a glossary change, rejected words found in code names are handed to `/docs-hygiene:rename-references` as their own change, and those in user-facing copy and error messages are reported, never rewritten.
