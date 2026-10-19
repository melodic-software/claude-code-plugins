---
bump: minor
---

### Added

- `funding`, a map from Claude lane id to its funding role (`reviews`, `automations` or
  `issue-lane`), whose `<ROLE>_CLAUDE_API_KEY` and `<ROLE>_CLAUDE_CODE_OAUTH_TOKEN` secrets a lane
  on ci-workflows' run-claude-cli action passes; intake is the first, and the other entries name
  the role each lane takes when it moves ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  `version` stays 2.
