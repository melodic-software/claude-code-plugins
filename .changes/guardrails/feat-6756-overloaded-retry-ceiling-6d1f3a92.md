---
bump: patch
---

### Changed

- `workflow-resilience-check`'s advisory also names `CLAUDE_CODE_OVERLOADED_RETRY_MAX_DELAY_MS`, the variable that sets Claude Code's own 529 retry backoff ceiling, and links the [Tune retry behavior](https://code.claude.com/docs/en/errors#tune-retry-behavior) section for its default and range. It is offered beside wave caps and `agentRetry`, not in place of them: the docs do not say whether workflow subagents honor it ([#6756](https://github.com/melodic-software/claude-code-plugins/issues/6756)).
