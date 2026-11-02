---
bump: minor
---

### Added

- `control-claude-code` takes `--unattended` on `launch`, `ready` and `logs`. It keeps the one CI credential variable that `credentials.ci` in `config/defaults.json` names (`ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`), sets `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, and the session holder unsets it once `claude` starts (its `/proc` environment still holds it); whether the plugin under test can still read it is left to #8651's isolation probe. Ready accepts that credential's `apiKeySource`, and the driver refuses to start when both variables are set. Attended runs are unchanged: the API-key, gateway and provider variables are cleared and Ready requires `none`.
