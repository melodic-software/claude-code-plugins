---
bump: minor
---

### Changed

- The `docs-fetcher` gate's `PreToolUse` `Bash` row sets `"onFailure": "block"`, so on Claude Code 2.1.295 or later a gate that cannot start because `node` is missing, or that reaches its 10 s timeout, denies the call instead of leaving `discovery:docs-fetcher` with an unchecked `Bash` ([#9982](https://github.com/melodic-software/claude-code-plugins/issues/9982)). The row matches every `Bash` call, so on such a host the main thread's `Bash` is denied too. An older client ignores the key.
