---
bump: minor
---

### Changed

- `/evals:design skill <name>` writes `case.yaml` cases in the eval directory of the plugin that ships the skill, one directory per case with a `prompt.md` and samples for each deterministic grader, and checks them with `/evals:validate`. It no longer writes a skill-creator `evals/evals.json`. A case's difficulty is a `hard` or `routine` tag, and its source and why it is hard go in its `description`. A new case, `de-skill-target-suite`, covers the skill target.
- `/evals:validate`, `/evals:plugin-eval`, `/evals:methodology` and the README treat the suite layout as the one eval format for a skill. A skill-creator JSON eval file is converted to case directories and then validated, no longer routed to `/skill-quality:check validate-evals`.
