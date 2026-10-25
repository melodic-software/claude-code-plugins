---
bump: minor
---

### Changed

- The bundled `generated` default is now empty. It named a regenerator inside the architecture plugin's skill folder, a path only this marketplace's own checkout has, so in any other repository the entry could not run. Declare generated files in the team layer, `.claude/docs-naming.json`.
- In a repository whose team layer declares no `generated` entry, `docs/architecture/landscape.json` is no longer treated as generated. Before, a rename with a site in it stopped before anything moved, because its regenerator resolved to nothing, and `--regenerate-only` failed. Now the sweep and the realign edit its references like any other file's. To keep it regenerated instead of edited, declare it in the team layer with your own regenerate command.
