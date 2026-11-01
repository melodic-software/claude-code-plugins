---
bump: minor
---

### Added

- triage: a `triage_stale_reporter_info_days` repository setting, off by default (#11868). When a repository sets it, the attention view lists each open `needs-reporter-info` item whose reporter lacks write access and has not replied within that many days as a close candidate. Triage closes a candidate only on the operator's yes in an attended session; a lane or CI run reports the list and closes nothing.
