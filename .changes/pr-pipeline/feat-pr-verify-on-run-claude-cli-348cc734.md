---
bump: minor
---

### Changed

- `pr-verify.yml` judges on ci-workflows' run-claude-cli action as the `automations` role, so its
  runs spend `AUTOMATIONS_CLAUDE_API_KEY` credits first and fall back to
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` after a credit stop
  ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  The model reads its data files from `pr-verify-data` in the working directory with Read alone,
  every other path and tool denied. No verdict is written when any leg hit a permission denial,
  or when the summary or notes hold text shaped like an Anthropic key or OAuth token, and a run
  that leaves no verdict fails. The
  artifact name and verdict JSON are unchanged. `version` stays 2.

### Added

- `resolve-config` outputs `model` and `effort` for run-claude-cli callers: `model` is empty for a
  `default` model, which the launcher cannot pass, and `effort` is empty when the profile sets
  none.
