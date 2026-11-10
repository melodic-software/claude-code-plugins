---
bump: patch
---

### Changed

- `/planning:interview`, `/planning:prd` and `/planning:plan` read the glossary through the `/domain-driven-design:ubiquitous-language lookup` read action, with a repository search (root, any `docs/` folder, the module folder) when that plugin is absent; `/planning:interview` and `/planning:design` write resolved terms through `/domain-driven-design:ubiquitous-language curate`.
