---
bump: patch
---

### Fixed

- The lane sweep's file job no longer drops a workflow-level finding (duplicate runs, reruns) from a slice D unit with green samples. A D unit's green samples do not list every job that ran, so `file-findings.mjs` now binds a D finding to its workflow only; slice A still binds the job to its runs' failed jobs.
