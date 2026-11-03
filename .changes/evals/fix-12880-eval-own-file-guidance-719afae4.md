---
bump: patch
---

### Fixed

- `/evals:plugin-eval` case guidance no longer says a reference read can be denied: a run reads its own plugin copy by absolute path, and only a pathless or workspace-relative lookup finds nothing
