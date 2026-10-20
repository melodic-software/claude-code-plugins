---
bump: patch
---

### Fixed

- `babysit_risk.DECLARATION_FILES` holds each plugin's `skills/*/SKILL.md`, `commands/**/*.md` and `agents/**/*.md`, read at the base SHA like the other declarations. While the HIGH floor applies, what they run joins it: the script each `!` command runs through `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_SKILL_DIR}` (as the directory holding it), and every path the body names under those variables (a script as its directory, any other file as itself). A `!` command whose program or script path is relative or built from another variable, a variable spelling the reader does not resolve, a reference leaving the plugin, shell text the reader cannot follow, a `!` command in a skill whose `shell` is not bash, or an unreadable body scores HIGH as `high-path:**`.
