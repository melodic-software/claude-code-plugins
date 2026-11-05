---
bump: minor
---

### Changed

- The lost-run reconciler re-runs a passed `pr-require-checks` run whose spec changed after its
  pass at attempt 1 or 2, so a spec that changes again after the reconciler's first re-run gets a
  fresh pr-verify judgment without a manual re-run. Each re-run is recorded as
  `reconcile-rerun-<run id>-<attempt>-<head>`, naming the attempt it starts. A run at attempt 3 is
  named in the summary for a person.
- check-trusted-trigger accepts a reconciler-recorded `github-actions[bot]` re-run at attempt 2 or
  3 (`RECONCILER_ATTEMPT_CAP`), on this run and on a `workflow_run` upstream; the record must name
  that attempt, and every other check of the record is unchanged.
