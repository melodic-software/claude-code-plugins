---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, after looking for a project `control-<app>` skill. It loads the match, project or plugin, through the Skill tool and reads its `features/` from the base directory the tool reports. A project skill with the same `control-<app>` name wins, and the report names the skill used and its source (project, plugin, or another path, where an unattended run stops).
- Drive reads a project control skill's `SKILL.md` before loading it and blocks one whose frontmatter grants tools, registers hooks or forks a subagent, or whose body runs a dynamic-context command. An unattended run with no `<app>` no longer drives a lone plugin control skill.
