---
bump: patch
---

### Changed

- The `verify-scripts` schema description no longer says code a listed script runs can read the token from an ancestor process: since [#11432](https://github.com/melodic-software/claude-code-plugins/pull/11432) no ancestor holds it, which a write-lane run confirmed ([#7919](https://github.com/melodic-software/claude-code-plugins/issues/7919#issuecomment-6642080194)). It now names the token the write runner's checkout keeps in `.git/config`.
