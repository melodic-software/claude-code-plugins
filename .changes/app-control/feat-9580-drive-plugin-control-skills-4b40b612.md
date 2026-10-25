---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, when the repository has no `control-<app>` of its own. It looks in the `skills/` and `commands/` folders of each enabled plugin `claude plugin list --json` reports, session-only plugins included, and reports a control skill a plugin defines only inline in its manifest as blocked. Repository control skills are found in `.claude/skills/` folders at any depth, the skills and `commands/` files of a plugin kept in a skills folder, and `.claude/commands/`, in this checkout and, in a worktree, the main checkout; git-ignored and uncommitted ones count, and matches in a submodule or a dependency folder such as `node_modules` do not. A repository control skill beats a plugin's. Drive reads every control skill from disk as data and never invokes one through the Skill tool. The report names the skill used and its source (project or plugin) with its path.
- Drive reports a control skill whose frontmatter grants tools, registers hooks or forks a subagent, or whose body holds a dynamic-context command, as a finding, and runs none of it.
