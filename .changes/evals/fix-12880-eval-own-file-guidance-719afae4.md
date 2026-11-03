---
bump: patch
---

### Fixed

- `/evals:plugin-eval` case guidance no longer says a reference read can be denied: a run reads a plugin copy staged outside git by absolute path (other copy locations are unmeasured), and a pathless or workspace-relative lookup finds nothing
