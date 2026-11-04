---
bump: patch
---

### Changed

- The stress-test eval suite's `sound-part` check in each of the 12 `st-*` cases is now an `llm` judge with a short rubric for that case, in place of a `not_contains` regex that kept misgrading ordinary wording. The defect graders stay regexes. `evals/plan-stress-test.md` records the method and its basis, and each case's `samples/sound-part.json` is now the judge's labeled answers for a calibration run. The empty-reply pass samples are gone, since calibration skips an empty answer, and a reply that quotes the `st-proposal-3` draft's claim that polling is fine and then rebuts it is now a must-fail answer ([#12925](https://github.com/melodic-software/claude-code-plugins/issues/12925)).
