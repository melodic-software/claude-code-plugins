---
bump: patch
---

### Fixed

- The `lint` skill no longer says the Bash tool returns a command's complete output into context. The rule
  stands (the pipe is the bound, so it belongs in the command); the reason now points at the Output
  limits section of the Claude Code tools reference for what a result returns inline.
