---
bump: patch
---

### Security

- `scripts/check-read-caller-keys.sh` now checks a read run's role secrets per caller. Every file of the run may name only the shared `fallback_claude_code_oauth_token`, `claude_code_oauth_token`, `claude_api_key` and `github_token`. A workflow whose run reaches `pr-run-activity-read.yml` may also name the role secrets in its own `CALLER_SECRETS` entry: `pr-refine.yml` and `pr-unblock.yml` the `pr_unblock_` names, `work-resolve-issue.yml` the `issue_lane_` names. Another lane's secret now fails with a message naming the caller and the secret. A workflow whose run reaches the read workflow with no entry in the map also fails.
