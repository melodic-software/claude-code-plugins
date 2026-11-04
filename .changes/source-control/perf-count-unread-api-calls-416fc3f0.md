---
bump: patch
---

### Fixed

- `babysit_gh.py` counts the GitHub requests of every call that gives no header block (a binary artifact download, a subcommand other than `gh api`, a bare `--paginate`). In a job that names its token, such a call runs with `GH_DEBUG=1`, each request to a GitHub API URL becomes a `request <route>` line in the token's api-budget file, and stderr comes back without the debug lines, as `api_budget_traced` does for the shell wrapper. The job's api-calls notice no longer leaves those requests out.
