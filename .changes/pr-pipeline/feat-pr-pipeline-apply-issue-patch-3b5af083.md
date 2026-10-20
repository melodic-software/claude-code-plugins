---
bump: minor
---

### Changed

- resolve-issue runs on the read runner with no write token: its model job holds only the job's
  read-only `GITHUB_TOKEN`, which
  [claude-code-action](https://github.com/anthropics/claude-code-action) needs, and no App token
  or `id-token`. Its uncommitted change leaves as a patch, collected also after a turn cap or a
  usage limit so a resumed run continues it. The earlier-work check, the issue file, the reuse
  path and the reuse summary pass move to the read runner with it
  ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
- The write runner refuses an issue skill, and its apply-patch select step runs the activity's
  own script from the base.

### Added

- `apply-issue-patch`: a script activity that runs
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  with the `issue` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  (now capped at 300 files). It makes a new `work-resolve-issue/issue-<n>-<run id>-<attempt>`
  branch at the commit the model worked on, with one commit, after re-reading the issue's hold
  labels and `agent-ready`, and names that branch in the run's `lane.json`. resolve-issue sets
  `applied-by` (`patch: apply-issue-patch`, `work-outcome: report-outcome`), and
  `activity-rules.json` refuses it any write effect.
