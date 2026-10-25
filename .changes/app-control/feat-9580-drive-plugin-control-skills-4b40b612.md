---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, when the repository has no `control-<app>` of its own. It loads a plugin skill through the Skill tool and reads its `features/` from the base directory the tool reports. A repository control skill always wins and is read from disk, never loaded: a `SKILL.md` in a `.claude/skills/` folder at any depth, the skills and `commands/` files of a plugin kept in a skills folder, and `.claude/commands/` files. Matches inside a submodule or a dependency folder such as `node_modules` are skipped; git-ignored and uncommitted ones are kept. Before loading any plugin skill, drive checks whether its plugin is a folder in the `.claude/skills/` of this checkout or of the main checkout of a worktree; such a skill is read from disk, or reported blocked when no file holds it (a manifest command), and never loaded. The report names the skill used and its source (project, plugin, or another path, where an unattended run stops).
- Drive reports a repository control skill whose frontmatter grants tools, registers hooks or forks a subagent, or whose body holds a dynamic-context command, as a finding, and runs none of it.
