---
bump: minor
---

### Added

- behavior-probes: a `subagent` area of live cases that test subagent effort precedence (session `effortLevel`, an agent definition's `effort:` pin, the Agent tool's per-spawn `effort` parameter, and `CLAUDE_CODE_EFFORT_LEVEL`), read from each PreToolUse hook payload's `effort.level`, plus a case recording that `${CLAUDE_EFFORT}` in a skill preloaded into a subagent expands to the session effort, not the subagent's.
