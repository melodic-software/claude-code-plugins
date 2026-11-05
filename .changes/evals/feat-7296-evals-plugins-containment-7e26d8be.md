---
bump: patch
---

### Fixed

- `/evals:validate` now fails a case whose `plugins` entry resolves outside the plugin under evaluation, or to a second plugin outside the case's own subdirectories, both of which `claude plugin eval` refuses to load, so the refusal shows before a paid run (#7296).
