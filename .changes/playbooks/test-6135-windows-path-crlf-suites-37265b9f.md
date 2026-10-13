---
bump: patch
---

### Fixed

- repo-sweep `tick.sh` and `state.sh` now pass `-b` to a native jq under Git Bash or Cygwin. A CRLF pull request body keeps its exact bytes, and the `branch` and `sweep` lines no longer end in a carriage return (#6135).
