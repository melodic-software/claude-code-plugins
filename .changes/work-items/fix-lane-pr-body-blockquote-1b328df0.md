---
bump: minor
---

### Changed

- `/work-items:work --issue <n> --ci`: `work-outcome.json` gains `changes`, `verification` and
  `not_done`. The mode runs the checks the runner names, writes an external fact only after reading
  its source in the run, and marks a required check it could not run or pass `required` in
  `not_done`, which the lane reports as `stopped`.
