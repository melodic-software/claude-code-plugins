---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, when the repository has no `control-<app>` of its own. It loads a plugin skill through the Skill tool and reads its `features/` from the base directory the tool reports. A repository control skill always wins and is read from disk, never loaded: a `SKILL.md` in a `.claude/skills/` folder at any depth, the skills and `commands/` files of a plugin kept in a skills folder, and `.claude/commands/` files, in this checkout and, in a worktree, the main checkout. Matches inside a submodule or a dependency folder such as `node_modules` are skipped; git-ignored and uncommitted ones are kept. Drive loads a control skill through the Skill tool only when its prefix names a plugin `claude plugin list` reports installed under the plugins root; any other candidate is reported blocked and never loaded. The report names the skill used and its source (project or plugin).
- Drive reports a repository control skill whose frontmatter grants tools, registers hooks or forks a subagent, or whose body holds a dynamic-context command, as a finding, and runs none of it.
