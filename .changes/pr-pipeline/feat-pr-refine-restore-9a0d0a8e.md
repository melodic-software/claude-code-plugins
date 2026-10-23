---
bump: minor
---

### Changed

- `fix-docs` moves from `pr-unblock` back into its own `pr-refine` lane (stage `refine`): `pr-refine.yml` holds the `fix-docs`, `fix-docs-subscription` and `apply-docs-patch` jobs, and `pr-unblock.yml` no longer takes `fix-docs`. `pr-unblock-dispatch.yml` dispatches `pr-refine.yml`, still once per PR and at most `limits.fix-docs-per-run` per run; a PR that already has a `pr-unblock / fix-docs` run counts as done.
- `fix-docs` now tidies every ready PR that changes Markdown, lanes App PRs included, except Dependabot's, the release App's and the standards-sync App's, matched by account id.
- Both activity runners name `pr-refine.yml` as the dispatched workflow for the `pr-refine` lane. pr-merge's refire of a broker `workflow-modified` refusal leaves `pr-refine` runs out: a `pr-refine` run is dispatched on main, so an empty commit on the PR cannot make it pass, and a listed person re-dispatches it.
