---
bump: patch
---

### Fixed

- The load probe and the adherence experiment use the repository's `node_modules/.bin/claude` only when it runs, and fall back to `claude` on PATH otherwise, so a root install with scripts off no longer leaves them on a stub that does not run.
