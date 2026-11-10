---
bump: patch
---

### Changed

- `/architecture:improve` reads the glossary through the `/domain-driven-design:ubiquitous-language lookup` read action, with a repository search (root, any `docs/` folder, the module folder) when that plugin is absent, and writes resolved terms through `/domain-driven-design:ubiquitous-language curate`.
