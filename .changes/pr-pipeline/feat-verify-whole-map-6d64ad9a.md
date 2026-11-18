---
bump: minor
---

### Added

- `maintenance-verify-whole-map.yml` runs `/testing:run-e2e map` on a listed human's dispatch, in the pull-request capture's sandbox, launch broker and key proxy on the pr-verify API key, under the capture's token caps and driven model. It takes `features`, `max_entries` (default 40, at most 100) and `baseline_run`, prints the entry count, the token caps, the driven model and the driver's turns before any model turn, and stops on the lanes kill switch. It keeps `findings.json` as `map-findings` for 90 days and the evidence as `map-evidence` for 7, and compares against the newest earlier pass's `map-findings`. Its driver leg takes the new run route `verify-map`, on the new `verify-map` profile (Opus, effort high, 300 turns).
