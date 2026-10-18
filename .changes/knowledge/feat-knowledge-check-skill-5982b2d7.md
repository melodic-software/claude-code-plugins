---
bump: minor
---

### Added

- `/knowledge:check`, a model-invocable read-only skill that reports, through the shared prerequisites checker, whether each tool `prerequisites.json` declares resolves. It installs nothing. `prerequisites.json` entries now name it as their re-check skill, and `video-digest`'s Prerequisites failure line names it beside the preflight.
