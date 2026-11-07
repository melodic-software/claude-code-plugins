---
bump: patch
---

### Changed

- Six eval cases held from the `evals.json` retirement ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)) are restored, with the owner's approval of their widened graders:
  - `confirm-fix-symptom-and-regression`: `names-regression` also accepts "existing tests ... pass" and "full suite ... pass/green".
  - `confirm-refactor-new-failure-surfaced`: `verdict-not-preserved` also accepts `Verdict: NEEDS WORK`, since a Stage 1 FAIL stops the run.
  - `confirm-parser-and-storage-checks`: `replays-saved-input` also accepts "run the new parser on real/saved inputs".
  - `confirm-live-workers-no-workspace-entry`: `report-line` accepts "user option" beside "userConfig".
  - `confirm-proof-level-user-strict-wins`: `report-line-strict` accepts "user option" beside "userConfig".
  - `measure-performance-baseline-capture`: `plan-records-baseline` lets the figure sit on the line after "baseline". Its scaffold clears `GIT_DIR`, `GIT_WORK_TREE` and `GIT_CONFIG` in its own shell before its git calls.
