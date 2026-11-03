---
bump: patch
---

### Fixed

- The four `ratchet-*` eval cases drop their `tool_used: Skill` grader: each prompt slash-invokes
  `/toolchain:ratchet`, which loads the skill without a Skill call, so the grader failed every run.
- The `ratchet-existing-performance-file` grader `joins-performance-file` no longer depends on key
  order: `ratchet.py add` writes `goal` before `ceiling`, so the grader failed every run that
  recorded the right ceiling.
