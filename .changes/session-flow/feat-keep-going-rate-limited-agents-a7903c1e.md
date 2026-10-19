---
bump: minor
---

### Added

- keep-going singles out every subagent or workflow agent whose last notification carries a rate-limit error, re-checks the live windows, reads its partial work, resumes it with `SendMessage` when its id resolves (restarting from its trail otherwise), and reports each with its evidence and one action.
