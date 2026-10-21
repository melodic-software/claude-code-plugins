---
bump: patch
---

### Fixed

- A red full run pr-merge.yml starts after a merge now reaches post-merge-demotion-alert.yml, so its
  record, fix issues and red-main report follow the merge instead of waiting for the next scheduled
  run. The run uses `GITHUB_TOKEN` and raises no `workflow_run` event, so pr-merge's
  `dispatch-full-run` job sends its run id through `workflow_dispatch`. The alert takes the id only
  from `github-actions[bot]` or a listed human, never the lanes App, and only for attempt 1 of a
  failed `pr-require-checks.yml` run on this repository's `main` that `github-actions[bot]`
  dispatched. It then waits up to `red-main.confirm-wait-minutes` for pr-merge's re-run and starts
  none of its own. When no re-run finishes in that wait and a newer `pr-require-checks` run on
  this repository's `main` has passed, `main` already recovered: it logs so and files no record,
  fix issue or report.
