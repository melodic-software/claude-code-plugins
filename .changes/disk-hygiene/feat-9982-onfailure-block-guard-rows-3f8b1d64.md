---
bump: minor
---

### Changed

- The two plugin-level destructive-guard rows for a command naming `hygiene.py` (`Bash` and `PowerShell`) set `"onFailure": "block"`, so on Claude Code 2.1.295 or later a guard that cannot launch because `node` or bash is missing, crashes, or times out denies the engine call instead of letting it run unchecked ([#9982](https://github.com/melodic-software/claude-code-plugins/issues/9982)). The `PowerShell(*python*$*)` and `PowerShell(*& $*)` rows keep the default, since they match commands that do not name the engine. An older client ignores the key.
