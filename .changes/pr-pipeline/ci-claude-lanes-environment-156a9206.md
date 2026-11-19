---
bump: minor
---

### Changed

- Every job that reads a Claude secret names the main-only `claude-lanes` environment with `deployment: false`, so a workflow file changed on another branch never reaches one; `scripts/check-claude-secrets-environment.sh` fails a job that reads one outside it, or a job in it that a `pull_request`, `merge_group` or off-main push run starts. A call to another repository's reusable passes when it sets `with: environment: claude-lanes`. PR Run Plugin Evals now starts on `workflow_run` from main: the `eval: run` label runs the secret-free `pr-run-plugin-evals-label.yml`, and the eval legs re-read the pull request, its label event and its actors from the API.
