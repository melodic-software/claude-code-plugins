---
bump: minor
---

### Added

- `recommend_skills_exclude` option: `none` (default), `disabled`, `not-installed` or `disabled,not-installed`. `/session-flow:recommend-skills` drops skills in those states from its menu and says which states it dropped.

### Changed

- `/session-flow:recommend-skills` builds its pool from `/harness-ops:inventory --skills-index`, which indexes every skill's frontmatter whether it is enabled, disabled or not installed. It shortlists from the index and reads only the shortlisted SKILL.md files. Disabled and not-installed skills are annotated `(disabled)` and `(not installed)`, replacing the `(plugin not enabled)` annotation. The skill asks at most one question and never enables or installs a skill.
