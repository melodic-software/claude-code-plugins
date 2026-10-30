---
bump: minor
---

### Changed

- Every `PreToolUse` guard row except `Workflow` sets `"onFailure": "block"`, so on Claude Code 2.1.295 or later a guard that cannot start because `node` or bash is missing, or that reaches its 60 s timeout, denies the call instead of letting it run unguarded ([#9982](https://github.com/melodic-software/claude-code-plugins/issues/9982)). An older client ignores the key and behaves as before. The hook-budget contract lists which rows set the key and why the rest do not.
