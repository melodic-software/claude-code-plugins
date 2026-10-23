---
bump: patch
---

### Fixed

- address-feedback's and review-dependency's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. As for fix-ci, `address-feedback-handoff` and `review-dependency-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API once, and the fallback call runs when the first call's report job posted no check ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).
- Every fallback call with a handoff job, fix-ci's among them, passes `fallback: handoff`, which the read runner now accepts, instead of a label taken from the first call's `lane-class`. Its lane record reads "posted no check" in place of "hit a credit stop" or "is empty" ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).
