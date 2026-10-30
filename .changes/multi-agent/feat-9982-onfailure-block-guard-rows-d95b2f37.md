---
bump: minor
---

### Changed

- The `drift-checker` fetch gate (`PreToolUse` `WebFetch`) and the `docs-fetcher` gate (`PreToolUse` `Bash`) set `"onFailure": "block"`, so on Claude Code 2.1.295 or later a gate that cannot start because `node` is missing, or that reaches its 10 s timeout, denies the call instead of letting it run unchecked ([#9982](https://github.com/melodic-software/claude-code-plugins/issues/9982)). Both rows match every call of their tool, so on such a host the main thread's `WebFetch` and `Bash` are denied too. An older client ignores the key.
