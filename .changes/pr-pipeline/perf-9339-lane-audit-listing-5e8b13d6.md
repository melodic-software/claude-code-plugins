---
bump: patch
---

### Fixed

- The lane sweep's collector keeps 184 calls for the open pull request and issue reads and the units, not 170: with four slice A units, no slice D unit and four slice C units they cost 4 + 4 × 5 × 7 + 4 × 10 calls, so that mix no longer runs out partway through its slice C units and marks the run incomplete ([#9339](https://github.com/melodic-software/claude-code-plugins/issues/9339)).

### Changed

- The collector reads each range's run count from its first page of 100 runs and keeps those runs, where it made a `per_page=1` count call and then read page 1 again, and it lists workflows busiest first, so a short budget leaves the smaller ones part-read (`.github/scripts/maintenance-audit-lane-runs/collect.mjs`).
