---
bump: patch
---

### Fixed

- `convert-evals-json.py` now grants each converted case the tools its skill needs: Bash when the SKILL.md holds a pre-computed context line or runs something through Bash, plus every tool in the skill's `allowed-tools` frontmatter, reduced to its tool name. A case for a skill with a pre-computed line used to get read-only tools, so the slash command failed to load and the run ended at 0 turns.
- `/evals:validate` warns when a case names a skill (a leading `/<plugin>:<skill>` or a tag) whose SKILL.md has a pre-computed context line and the case's `allowed_tools` lacks Bash.
