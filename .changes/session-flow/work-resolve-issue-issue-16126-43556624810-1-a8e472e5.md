---
bump: patch
---

### Fixed

- `/session-flow:retro session` judges each line it assesses in `CLAUDE.md`, `AGENTS.md` or a rules file against `/docs-hygiene:write-for-agents`. When that skill is not available, the report now says so whenever it assesses such a line, a no-op row or a judgment call included; before, only a finding triggered it. The `says-no-yardstick` grader of the `re-session-noop-steering-line` eval looks for this statement, and no measured run had made it.
