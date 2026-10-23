---
bump: minor
---

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run once when its first attempt failed on anything but infra, so a flaky test the diff did not cause costs no model run ([#9271](https://github.com/melodic-software/claude-code-plugins/issues/9271)). Its attempt number caps it at one re-run per run and head; a run where only ci-status failed gets none.
- fix-ci waits for that re-run before it takes a head, and also takes a head whose ci-status passed but whose advisory pr-test-windows run failed again, since the merge gate holds a pull request on any failing check.
