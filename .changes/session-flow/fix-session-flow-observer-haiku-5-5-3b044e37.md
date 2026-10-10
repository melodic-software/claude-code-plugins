---
bump: minor
---

### Added

- `observer_analysis_effort` sets the effort level of the observer's post-session analysis run,
  passed as `--effort` (default `medium`). The run drops `CLAUDE_CODE_EFFORT_LEVEL` from its
  environment, because that variable overrides `--effort`
  ([env-vars precedence](https://code.claude.com/docs/en/env-vars#precedence)).

### Changed

- The observer analysis model (`observer_analysis_model`) now defaults to `claude-opus-5-5`
  instead of `claude-haiku-4-5`, which Anthropic may retire as early as 2026-10-15
  ([model deprecations](https://platform.claude.com/docs/en/about-claude/model-deprecations)).
  It was chosen for faithful findings: in a four-session local pilot against Haiku 5.5 and
  Sonnet 5.5, Opus 5.5 at medium effort missed the fewest important findings and invented the
  fewest events.

### Fixed

- The analysis run now counts as failed, keeping the observations and writing nothing to the
  ledger, when its output is not JSON, its `terminal_reason` is present and not `completed`, its
  `subtype` is not `success`, or it reports any `permission_denials`. Non-JSON output was
  previously written to the ledger as findings.
