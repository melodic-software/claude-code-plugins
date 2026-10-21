---
bump: patch
---

### Fixed

- A red full run pr-merge.yml starts after a merge now reaches post-merge-demotion-alert.yml, so its
  record, fix issues and red-main report follow the merge instead of waiting for the next scheduled
  run. The run uses `GITHUB_TOKEN` and raises no `workflow_run` event, so pr-merge's
  `dispatch-full-run` job sends its run id through `workflow_dispatch`. Red is every conclusion
  `babysit_postmerge.py` counts as failed (`failure`, `timed_out`, `cancelled`, `startup_failure`,
  `action_required`), so a run cancelled on a time-budget overrun files its record and fix issues
  too; the red-main report still takes only `failure`. The alert takes the id only from
  `github-actions[bot]` or a listed human, never the lanes App, and only for attempt 1 of a red
  `pr-require-checks.yml` run on this repository's `main` that `github-actions[bot]` dispatched.
  pr-merge re-runs such a run only inside a lane merge's attribution window, so the alert waits up
  to `red-main.confirm-wait-minutes` for a re-run and starts none of its own. When no re-run
  finishes in that wait and a newer `pr-require-checks` run on this repository's `main` has passed,
  `main` already recovered: it logs so and files no record, fix issue or report.
