---
bump: patch
---

### Changed

- The eval lane runs on a new `maintenance` funding role, `MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN`. The judge lane stays on `automations`, which remains the default role for any lane without a dedicated one. `.github/lane-funding.json` lists both, and the [pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding) names them.
