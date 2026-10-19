---
bump: minor
---

### Added

- `/knowledge:check`, a model-invocable read-only skill that reports, through the shared prerequisites checker, whether each tool `prerequisites.json` declares resolves. Its check installs nothing; after the report it offers each missing row's fix and runs it only on the user's yes. `prerequisites.json` entries now name it as their re-check skill, and `video-digest`'s Prerequisites failure line names it beside the preflight.
