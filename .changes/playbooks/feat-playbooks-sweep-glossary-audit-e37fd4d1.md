---
bump: minor
---

### Added

- `repo-sweep` hygiene catalog: a read-only `glossary` step runs `/domain-driven-design:ubiquitous-language audit` where the repository has a ubiquitous-language glossary. Its fixes go through `curate` and `/docs-hygiene:rename-references` in their own change.
