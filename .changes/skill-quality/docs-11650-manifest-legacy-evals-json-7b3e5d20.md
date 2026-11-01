---
bump: patch
---

### Changed

- The plugin description calls the `evals.json` schema check and lint legacy, for per-skill files not yet converted, and points new eval cases at the plugin suite format that `/evals:validate` checks.
- `/skill-quality:check validate-evals` no longer says check 14 fails a skill whose only evals are suite cases; under `--require-evals` it passes when a suite case's `tags:` names the skill.
