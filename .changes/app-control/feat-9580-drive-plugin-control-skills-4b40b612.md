---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, when the repository has no `control-<app>` of its own. It loads a plugin skill through the Skill tool and reads its `features/` from the base directory the tool reports. A repository control skill always wins and is read from disk, never loaded, wherever the repository keeps it: the root skills folder, a nested one, or a command file. The report names the skill used and its source (project, plugin, or another path, where an unattended run stops).
- Drive reports a repository control skill whose frontmatter grants tools, registers hooks or forks a subagent, or whose body holds a dynamic-context command, as a finding, and runs none of it. An unattended run with no `<app>` no longer drives a lone plugin control skill.
