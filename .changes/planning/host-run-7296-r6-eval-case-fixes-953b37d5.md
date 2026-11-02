---
bump: patch
---

### Fixed

- Eval cases `interview-coded-terms-round-answerable`, `interview-context-unfamiliar-term-upstream`
  and the three `brainstorm-*` cases whose prompt slash-invokes the skill drop their `tool_used:
  Skill` grader: a slash-invoked skill loads without a Skill call, so that grader failed every run.
- Eval cases `interview-round-topic-groups-index` and `interview-scope-cut-moscow` raise
  `max_turns` from 12 to 30 and `timeout_seconds` to 900: their passing runs needed 19 to 20
  turns, and 4 of 6 runs stopped at the cap mid-round.
