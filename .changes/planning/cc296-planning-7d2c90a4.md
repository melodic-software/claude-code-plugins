---
bump: patch
---

### Fixed

- **The plan reviewer's effort record is current again.** The `plan-reviewer` agent justified its effort pin by saying the Agent tool takes no per-call effort, which stopped being true in Claude Code 2.1.292. The agent now states our decision instead: the pin sets the reviewer's level and `/planning:plan` passes no `effort` on the dispatch, with a pointer to the subagents docs section on effort for the live precedence. `/planning:plan` step 3 says the same.
