---
bump: minor
---

### Added

- hold credentialed workflows and workflow privilege gains for a person

  Every workflow that names a secret other than GITHUB_TOKEN, mints a lane
  token, or grants `actions: write` (which dispatches those), the review
  workflows themselves and ci-status (`pr-require-checks.yml`) are now `gate`
  floor paths held for a person: 23 workflows. A workflow
  change that gains a write scope (or drops a permissions block onto the
  repository default) holds as `permission-widening-review`, and one that
  adds a pull_request_target or workflow_run trigger as
  `privileged-trigger-review`; both are person codes no cost decision
  clears. A secrets reference is also read from the head text, so a
  workflow with no patch is not skipped.

- bind a lane-source pull request's reviews to a run from main

  A pull request that changes a lane source (a workflow, Claude Code config,
  the review criteria) now binds each review lane on the verdict artifact a
  run of main's pr-review-main.yml uploaded for its exact head: the run's
  path, workflow_run event, default branch, repository and completed
  success, its head held by main, and the verdict's lane, pull request and
  tree. Comments, markers and pull_request runs never count for it. The
  most findings any main-run review of the head's tree reported count, so a
  re-run never clears one. With no such verdict it stays unbound as before;
  an enforcement path beside it now waits for that review instead of a
  person (`review-path-unbindable` is gone). ci-status's own workflow is a
  `gate` path, so no review verdict clears it.
