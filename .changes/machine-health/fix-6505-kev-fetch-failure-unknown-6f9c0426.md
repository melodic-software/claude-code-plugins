---
bump: patch
---

### Fixed

- **A failed CISA KEV fetch no longer reads as a clean KEV check in `winget-upgrades` ([#6505](https://github.com/melodic-software/claude-code-plugins/issues/6505)).** `Get-CisaKevCache` now tags its result `fresh`, `stale`, `unavailable` or `empty`, with the list's age and the fetch error. With upgrades pending and no usable KEV list, the check reports `UNKNOWN` with `ran_successfully: false` and the cause in `error`, keeping the measured upgrades in `detail`, where it used to report a count-only `INFO` or `WARN` at full confidence. A stale fallback list keeps its severity but is named in the summary, `notes` and `detail.kev_cache_state`.
