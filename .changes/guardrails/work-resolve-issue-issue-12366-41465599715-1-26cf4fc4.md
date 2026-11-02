---
bump: patch
---

### Fixed

- The pre-commit and pre-push content checks and the hardcoded-path hook no longer block the home
  directory of the `runner` user on GitHub-hosted Linux runners, or a path under it. Every hosted
  runner uses that home directory, so it does not identify a person or a machine. A merge commit that
  brings in a file containing it now passes. A longer segment such as `runner2`, and any other user
  home on the same line, still blocks.
