---
bump: patch
---

### Changed

- The `api-routes` job-end notice keeps a workflow file name after `workflows/` (`repos/{repo}/actions/workflows/pr-verify.yml/runs`) instead of `{x}`, in `rate-guard.mjs` `routeOf` and `routeOk`, `api-budget.bash` `API_BUDGET_ROUTE` and pr-require-checks' generated copies. The calls a job spends listing runs can now be told apart by workflow. Only a lowercase `.yml` or `.yaml` file name is kept; a numeric workflow id stays `{n}`, any other segment stays `{x}`, and a route that would pass 80 characters keeps `{x}` there.
