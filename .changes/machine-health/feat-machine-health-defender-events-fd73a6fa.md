---
bump: minor
---

### Changed

- `defender` now reads detection history from the Defender event log, so detections older than Defender's own purge window still show: a recent detection with no recorded remediation is CRIT, a remediated one WARN, an older one INFO, and exclusion changes are listed as history (values in `latest.json` only, counts in the report); `defender-exclusions` lists each exclusion as a mutable item and reports `list_state: masked` when unelevated instead of a reading.
