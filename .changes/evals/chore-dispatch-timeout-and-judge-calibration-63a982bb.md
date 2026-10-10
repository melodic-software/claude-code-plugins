---
bump: patch
---

### Changed

- `plugin-eval`: calibrate every LLM-judge grader before the first full suite run, treat the default judge as uncalibrated until it passes, and move the whole suite to a stronger judge on a miss. Observed twice in #6669's eval gate: the default Haiku judge marked uc3 below baseline in a full run, then agreed with its labels on only 66.7% of calibration runs; a Sonnet judge calibrated at 100% and the next full run passed.
