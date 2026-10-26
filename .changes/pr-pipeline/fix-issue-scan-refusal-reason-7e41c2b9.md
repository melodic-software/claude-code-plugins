---
bump: patch
---

### Fixed

- An issue lane run whose scan job refused its output (a patch over its 262144-byte cap, a leak-scan block, a payload that does not match its record) is now handed back naming that refusal instead of "The run wrote no readable outcome file". The read runner's `scan-refusal` job now uploads its `scan-refused-<lane>-<activity>-<attempt>` marker in issue mode too, the write runner downloads the `resolve-issue` markers for `report-outcome`, and `report-outcome.mjs` reads them only for a run that left no readable outcome (`.github/workflows/pr-run-activity-read.yml`, `.github/workflows/pr-run-activity-write.yml`, `.github/scripts/work-resolve-issue/report-outcome.mjs`).
