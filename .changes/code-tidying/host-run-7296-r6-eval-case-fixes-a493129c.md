---
bump: patch
---

### Fixed

- Eval case `bs-no-task-tools-fallback` drops its `tool_used: Skill` grader: its prompt
  slash-invokes `/code-tidying:batch-simplify`, which loads the skill without a Skill call, so the
  grader failed every run.
