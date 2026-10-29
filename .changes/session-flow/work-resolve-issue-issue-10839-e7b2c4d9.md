---
bump: patch
---

### Changed

- `/session-flow:audit-sessions`: Step 2 now passes the sweep's `--catalog` only the installed skills that `reference/sweep-rules.json` or the correction lens suggests, in place of every skill in the session's listing. `sweep.py` checks no other name, and the skill's evals now expect the shorter list (#10839).
