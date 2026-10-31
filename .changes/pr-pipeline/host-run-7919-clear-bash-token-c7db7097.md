---
bump: patch
---

### Security

- The write runner's skill step sets `GH_TOKEN` and `GITHUB_TOKEN` to empty in its settings' `env`, so no Bash process holds the effect-scoped App token in its `/proc/<pid>/environ`, the sandbox's pid 1 and the Bash shell above a `verify-scripts` wrapper included. claude-code-action's MCP servers, commit signing among them, still get the token from their own config `env`. Under run-claude-cli, code a listed script runs can still read the job's read-only token from an ancestor ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#skill-activities)).
