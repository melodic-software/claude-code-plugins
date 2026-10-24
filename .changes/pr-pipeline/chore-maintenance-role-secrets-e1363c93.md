---
bump: patch
---

### Changed

- The eval and judge lanes run on a `maintenance` funding role, `MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN`, in place of `automations`, which is retired. `.github/lane-funding.json` lists the new role, and the [pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding) names it.
