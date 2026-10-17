---
bump: minor
---

### Added

- `/harness-ops:morning-brief` gains a Lanes section: per lane workflow over the last 7 days, runs, failures by class (rate-limit, max-turns, auth, other), limit stops, restarts and items with 3 or more limit stops (an item is a pull request run's head, else the event and the `#N` that ends the run title), then turn headroom (max and p90 turns against the max-turns cap) with a `CHECK` line and run links when a run hit max-turns or the p90 is at or above 80% of the cap. A run the action stopped for exceeding its turn cap counts as max-turns whatever class the lane record gives. New flags: `--lane-workflows`, `--lane-read-limit`, and the fixture flags `--lane-runs-json` and `--lane-annotations-json`.
