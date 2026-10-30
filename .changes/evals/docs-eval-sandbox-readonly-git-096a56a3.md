---
bump: patch
---

### Changed

- plugin-eval: the sandbox records add the Claude Code 2.1.310 and 2.1.314 observation that a Bash-granting run sees the scratch repo's `.git` (and, on 2.1.314, the session tmp directory) as read-only, and a Gotchas pointer to it.
