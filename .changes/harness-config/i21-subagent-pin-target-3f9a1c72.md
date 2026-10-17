---
bump: minor
---

### Changed

- `audit-instructions` I21: a `high` effort pin that targets subagents is judged against the model each subagent runs on, and the effort its definition sets, rather than only the session's resolved target. Eval case 34 gains a subagent-on-a-different-model run.
