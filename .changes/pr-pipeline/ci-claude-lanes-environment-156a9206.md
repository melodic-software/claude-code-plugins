---
bump: minor
---

### Changed

- Every job that reads a Claude secret names the main-only `claude-lanes` environment with `deployment: false`, so a workflow file changed on another branch never reaches one; `scripts/check-claude-secrets-environment.sh` fails a job that reads one outside it, or a job in it that a `pull_request`, `merge_group` or off-main push run starts. PR Run Plugin Evals' label trigger moves from `pull_request` to `pull_request_target`, which runs main's copy of the file.
