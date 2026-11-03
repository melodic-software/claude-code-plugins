---
bump: patch
---

### Fixed

- The four `ratchet-*` eval cases drop their `tool_used: Skill` grader: each prompt slash-invokes
  `/toolchain:ratchet`, which loads the skill without a Skill call, so the grader failed every run.
