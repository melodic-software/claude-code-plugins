---
bump: patch
---

### Fixed

- **The setup skill loads under `claude -p` again.** Its `node --version` and `npm --version`
  pre-computed rows were brace groups holding a quoted fallback, which Claude Code's shell
  permission check refuses (`Contains brace with quote character (expansion obfuscation)`); outside
  auto mode that aborts the whole skill with no output. The rows are now
  `node --version 2>/dev/null || echo unavailable` (and the `npm` twin), which render the same value.
