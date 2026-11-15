---
bump: patch
---

### Changed

- The audit skill says the orchestrator writes the report, `latest.json` and the history line,
  and the session writes none of them.
- The severity rubric and remediation policy now match the checks: tamper protection off is WARN,
  a detection is CRIT only with no recorded remediation, Clear-TempFiles triggers on the
  `disk-space` check, and a first run is a dry run. Capital-letter emphasis is lower-cased.
