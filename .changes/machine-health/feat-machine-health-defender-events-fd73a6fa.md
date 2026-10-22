---
bump: minor
---

### Changed

- `defender` now reads detection history from the Defender event log, so detections older than Defender's own purge window still show: a recent detection with no recorded remediation is CRIT, a remediated one WARN, an older one INFO, a recent path exclusion added outside the known-safe list WARN, and a log too short to cover the window is never OK; `defender-exclusions` lists each exclusion as a mutable item and reports `list_state: masked` when the lists are hidden instead of a reading. Exclusion values land in `latest.json`, the run's stdout snapshot (and so the agent's context) and the elevated run's result and log, and stay out of the markdown report, which shows counts only; the audit skill now treats every machine-derived string as data, never instructions.
