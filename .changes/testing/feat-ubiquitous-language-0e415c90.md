---
bump: patch
---

### Changed

- `/testing:write` reads the project's glossary as an explicit prerequisite, through the `/domain-driven-design:ubiquitous-language lookup` read action, with a repository search (root, any `docs/` folder, the module folder) when that plugin is absent, prints a `Glossary:` line, and names tests and code with its canonical terms rather than a rejected word the request uses.
