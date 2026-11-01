---
bump: patch
---

### Changed

- The plugin description calls the `evals.json` schema check and lint legacy, for per-skill files not yet converted, and points new eval cases at the plugin suite format that `/evals:validate` checks.
- `/skill-quality:check validate-evals` no longer says check 14 fails a skill whose only evals are suite cases; under `--require-evals` it passes when a case in the plugin's `evals/` lists the skill's directory name in a one-line `tags: [...]`. The README's check 14 line says the same.
