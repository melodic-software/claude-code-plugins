---
bump: patch
---

### Fixed

- The post-merge check no longer drops a red job when the jobs API lists its steps empty or cut short. A failed job that lists no failed step now counts as a failing check of its own, as a failed non-hygiene step does, so a job failing only on the gitleaks gate is still charged when its steps are missing. With the full step list, the hygiene-aggregate rule is unchanged. Such a job still excuses no test suite.
