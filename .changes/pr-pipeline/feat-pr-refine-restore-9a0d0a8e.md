---
bump: minor
---

### Changed

- `fix-docs` moves from `pr-unblock` back into its own `pr-refine` lane (stage `refine`): `pr-refine.yml` holds the `fix-docs`, `fix-docs-subscription` and `apply-docs-patch` jobs, and `pr-unblock.yml` no longer takes `fix-docs`. `pr-unblock-dispatch.yml` dispatches `pr-refine.yml`, still once per PR and at most `limits.fix-docs-per-run` per run; a PR that already has a `pr-unblock / fix-docs` run counts as done.
- `fix-docs` now tidies every ready PR that changes Markdown, lanes App PRs included, except Dependabot's, the release App's and the standards-sync App's, matched by account id.
- Both activity runners name `pr-refine.yml` as the dispatched workflow for the `pr-refine` lane. pr-merge's refire of a broker `workflow-modified` refusal leaves `pr-refine` runs out: a `pr-refine` run is dispatched on main, so an empty commit on the PR cannot make it pass, and a listed person re-dispatches it.

### Security

- `fix-docs-subscription` no longer starts on `fix-docs` outputs, which its head-code run job could forge. A `fix-docs-handoff` job reads this run's jobs through the Actions API, as `fix-ci-handoff` does for fix-ci. The fallback runs only when the broker allowed `fix-docs` and its report job posted no check (#8890).
- `apply-docs-patch` no longer takes its patch inputs or head from `fix-docs` run-job outputs. It takes them from the answering leg's scan job and the head from `fix-docs-head`, as fix-ci's `apply-patch` does (#8890).
