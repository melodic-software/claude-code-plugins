---
bump: patch
---

### Changed

- `plugin-eval`: `## Run` now calibrates judges before the full-suite run, and on a miss fixes the rubric or moves the run to a stronger `--judge-model`. The rule covers every LLM-judge grader the calibration harness can reproduce (labeled samples, judging text), treats the default judge as uncalibrated until it passes, and reports graders it cannot reproduce as uncalibrated. Observed twice in #6669's eval gate: the default Haiku judge marked uc3 below baseline in a full run, then agreed with its labels on only 66.7% of calibration runs; a Sonnet judge calibrated at 100% and the next full run passed.
