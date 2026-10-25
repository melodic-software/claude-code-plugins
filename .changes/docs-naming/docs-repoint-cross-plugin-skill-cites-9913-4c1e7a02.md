---
bump: patch
---

### Changed

- The bundled `generated` default is now empty. It named a regenerator inside the architecture plugin's skill folder, a path only this marketplace's own checkout has, so in any other repository the entry could not run. Declare generated files in the team layer, `.claude/docs-naming.json`.
