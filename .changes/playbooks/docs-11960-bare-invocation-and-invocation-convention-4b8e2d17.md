---
bump: patch
---

### Changed

- The skill criteria state the bare-invocation rule (infer the action; a read-only action proceeds
  and names what it inferred; a state change proposes and waits; unattended, a state change stops
  and reports) and the invocation convention (an automation starter is a reason against
  `disable-model-invocation: true`; the invocation-mode rubric's exception classes decide, and
  listing starvation alone is not one).
