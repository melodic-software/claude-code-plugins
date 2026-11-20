---
bump: patch
---

### Removed

- No job names the `claude-lanes` environment any more: every lane reads its Claude secrets from the organization copies again, `scripts/check-claude-secrets-environment.sh` and its `Lint Repo` step are gone, and `check-read-caller-keys` no longer admits that environment. PR Run Plugin Evals still starts on `workflow_run` from main.
