---
bump: patch
---

### Changed

- `/work-items:triage` and `/work-items:decompose` read the glossary through the `/domain-driven-design:ubiquitous-language lookup` read action, with a repository search (root, any `docs/` folder, the module folder) when that plugin is absent.
