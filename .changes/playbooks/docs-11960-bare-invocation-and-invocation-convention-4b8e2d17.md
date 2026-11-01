---
bump: patch
---

### Changed

- The skill criteria state the bare-invocation rule (infer the action; a read-only action proceeds
  and names what it inferred; a state change proposes and waits; unattended, a state change stops
  and reports) and the invocation convention (any automation starter makes a skill
  model-invocable; user-invoked only when starved and no automation starts it).
