---
bump: minor
---

### Added

- behavior-probes: a `subagent/skill-tool-skill-placeholder-effort` case for `${CLAUDE_EFFORT}` in a skill a subagent pinned `low` loads through the Skill tool, with the session at `medium`. Its live run on Claude Code 2.1.310 showed the subagent's `low`, while a rerun of the preloaded case on the same version still read the session's `medium`; `records.md` gains records 14 and 15.
