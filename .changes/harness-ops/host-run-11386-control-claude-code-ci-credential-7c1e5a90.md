---
bump: minor
---

### Added

- `control-claude-code` takes `--unattended` on `launch`, `ready` and `logs`. It keeps the one CI credential variable that `credentials.ci` in `config/defaults.json` names (`ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`) and sets `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, so the plugin under test's hooks, Bash and MCP servers do not get it. Ready accepts that credential's `apiKeySource`, and the driver refuses to start when both variables are set. Attended runs still clear every credential and require `none`.
