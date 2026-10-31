---
bump: patch
---

### Changed

- `/skill-quality:check validate-evals` says it reads only the skill-creator file a skill may still carry, and points new evals at `case.yaml` cases in the plugin's `evals/` directory, written by `/evals:design` and checked by `/evals:validate`. The plugin's first eval case, `ve-new-evals-route-to-suite`, covers that pointer.
