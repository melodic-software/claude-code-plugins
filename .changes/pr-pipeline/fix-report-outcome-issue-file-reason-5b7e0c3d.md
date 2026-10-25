---
bump: patch
---

### Fixed

- report-outcome names why an issue run never started. Before, it said only that the run wrote no readable outcome file. When write-issue refuses because the issue's title or body changed after `agent-ready` was added, it now sets `refused=edited`, and the run job's collect step records class `issue-edited` in `lane.json`. Any other write-issue failure records `issue-file`. The run job now copies the output sealer even after an earlier step failed, so that `lane.json` is sealed and published; before, the carry step found no sealer, and the scan job refused the unsealed payload. report-outcome's hand-back comment then says the run did not start and why. A record of either class counts only for a run that left no outcome of its own (`.github/scripts/work-resolve-issue/write-issue.mjs`, `.github/scripts/work-resolve-issue/report-outcome.mjs`, `.github/workflows/pr-run-activity-read.yml`).
