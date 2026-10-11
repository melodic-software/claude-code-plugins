---
bump: patch
---

### Changed

- The `implementer` and `phase-verifier` agents and the `implement-dispatch` holdout-tests, command-evidence and native-batch references point at the exact Claude Code docs sections for subagent turn caps, subagent effort, `disallowedTools`, PostToolUse and PostToolUseFailure, the test-writer split and the bundled `batch` skill, instead of restating them. The verifier's reason for setting no `maxTurns` no longer claims a capped run stops with no error.
