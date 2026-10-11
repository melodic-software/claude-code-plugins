---
bump: major
---

### Changed

- **Breaking:** the inlined rate-limit floor makes pausing opt-in. A lane pauses at 95% only when its session environment sets `LOOP_LANE_RATE_LIMIT_PAUSE=1`. Without it, the lane keeps working at the same model, effort and review depth, and reports the window, its reset time and the options: continue, switch accounts, or opt in (#7118).
