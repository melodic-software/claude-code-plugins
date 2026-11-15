---
bump: patch
---

### Changed

- The convention names the read runner's broker jobs, the issue lane's admission gate, the
  main-run review's gate job and the hosted review callers' kill-switch job by their verb-first
  ids: `check-broker` (was `broker-check`), `record-broker-allow` (was `broker-allowed`),
  `check-admission` (was `admit`), `check-trigger` (was `trigger`) and `check-kill-switch` (was
  `kill-switch`). The "The check-broker job" section replaces "The broker-check job". Each job's
  display name is its id in Title Case. Skip reasons, gate keys and limit keys named
  `kill-switch` are unchanged.
