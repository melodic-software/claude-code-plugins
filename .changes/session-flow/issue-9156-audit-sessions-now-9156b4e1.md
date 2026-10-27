---
bump: minor
---

### Added

- `/session-flow:audit-sessions now` audits the current session against the sweep's rules, so you can change course before the session ends. It collects only this session, by the id from `${CLAUDE_SESSION_ID}`, and stops without collecting when that id does not expand. It reports the per-session metrics, with each finding over its threshold.
- `sweep.py --session <id>...` limits metrics and findings to the named sessions. Each row's store p90 still covers every interactive session in scope, and the drift check still reads every record. The machine-wide cache ratio and per-PR churn are reported as not applicable, and `--write-report` is refused.
