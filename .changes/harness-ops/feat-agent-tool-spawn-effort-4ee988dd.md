---
bump: minor
---

### Added

- behavior-probes: a `subagent` area of five live cases that test subagent effort precedence (session `effortLevel`, an agent definition's `effort:` pin, the Agent tool's per-spawn `effort` parameter, and `CLAUDE_CODE_EFFORT_LEVEL`), reading the level from a preloaded skill's `${CLAUDE_EFFORT}` and, independently, from each hook payload's `effort.level`.
