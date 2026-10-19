---
bump: minor
---

### Added

- `models.issue-dimensions` budgets a run on an issue from its Size, Complexity and Uncertainty
  org issue fields, read by field and option id: turn cap = the size's `base-turns` times the
  complexity factor, rounded up, and the size's `timeout-minutes`. A field with no value, or whose
  latest setter is neither a listed human nor the lanes App, is not assessed, and an unmapped
  option fails the resolve (`unmapped-dimension`). New skip reasons, before any model turn:
  `not-assessed`, `research-first` and `probe-first` (Uncertainty Knowable and Unknown) and
  `split-required` (Size Large). This repository sets `small` (75 base turns, 50 minutes),
  `medium` (150, 100), `large` (`split`), and complexity factors 1, 1.5 and 2.
  work-resolve-issue.yml reads the fields (`issues: read`) and the timeout before its run job
  starts and passes the new `issue-dimensions` input on, so a field set while the run waits
  cannot outgrow the timeout, which is 25 minutes without `issue-dimensions`. No lane reads a
  `size:` label. A run that reaches its turn cap with no outcome of its own now leaves a
  `turn-cap` marker naming the cap and the branch, and the `pipeline/resolve-issue` status says so.
  `limits.turn-cap-restarts` (0 to 5, default 0) is how many times work-unblock restarts such an
  issue since a listed human last added `agent-ready`; past it the issue goes to a person, and this
  repository sets 0. The next run after a `turn-cap`, `stopped` or `limited` marker resumes from
  that run's lane branch when every commit on it ahead of the default branch is the lanes App's
  verified commit, and `issue.json` gains `resume`; a resumed run that reports `done` with no commit
  of its own opens no PR: the runner checks only the run's own branch, so it goes to a person naming
  the resumed branch. A run that exits non-zero on a funding stop
  (`api_error_status` 400 with "regain access on <date>", or 401) leaves a `funding` marker, keeps
  `agent-ready`, counts toward `limits.limit-stops-per-issue` (not `turn-cap-restarts`), and work-unblock restarts it after
  the date; `lane.json` gains `failed`, `api-error-status` and `error-text`
  ([README, Models](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#models); [pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
  `version` stays 2.
