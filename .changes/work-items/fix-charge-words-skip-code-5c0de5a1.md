---
bump: patch
---

### Fixed

- `rule-admit.sh` and intake admission no longer refuse an issue for a charge word inside a fenced code block or an inline code span (a job or file name such as `fix-ci-subscription`); the same word in prose still refuses. A plain "hosted runner" or "macOS minutes" now refuses only on a repository whose visibility does not read public, where standard GitHub-hosted runner minutes bill; larger and self-hosted runners still refuse everywhere. `charge-words.json` gains the `code` and `cost_private` patterns, and a definition missing either exits 8.
