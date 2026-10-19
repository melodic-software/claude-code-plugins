---
bump: minor
---

### Added

- `funding`, a map from Claude lane id to its funding role (`reviews`, `automations` or
  `issue-lane`), whose `<ROLE>_CLAUDE_API_KEY` and `<ROLE>_CLAUDE_CODE_OAUTH_TOKEN` secrets the
  lane passes to ci-workflows' run-claude-cli action ([README.md, Funding](README.md#funding)).
  `version` stays 2.
