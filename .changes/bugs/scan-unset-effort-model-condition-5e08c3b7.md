---
bump: patch
---

### Fixed

- `/bugs:scan`: a gate always passes an effort, its role's or the session's level when that is
  higher, so it holds the session's effort wherever the harness places it. Hunters still pass none,
  and the skill claims no level for them: `CLAUDE_CODE_SUBAGENT_MODEL` or a mod's `agent.spawn` can
  place a spawn on another model, where the session level does not apply. The run metadata labels
  a stage that passed none `unset`.
