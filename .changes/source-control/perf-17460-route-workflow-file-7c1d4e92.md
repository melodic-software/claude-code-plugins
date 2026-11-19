---
bump: patch
---

### Changed

- The route `babysit_gh.py` records for a `gh api` reading keeps a workflow file name after `workflows/` (`repos/{repo}/actions/workflows/pr-verify.yml/runs`) instead of `{x}`, so a job's `api-routes` notice shows which workflow's runs were listed. Only a lowercase `.yml` or `.yaml` file name is kept; a numeric workflow id stays `{n}`, any other segment stays `{x}`, and a route that would pass 80 characters keeps `{x}` there.
