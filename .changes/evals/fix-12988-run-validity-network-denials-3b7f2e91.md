---
bump: patch
---

### Fixed

- `/evals:plugin-eval` run-validity counts a with-arm Bash result's sandbox network denial as a permission denial and names the denied hosts in the summary: it is a FAIL, and a warning in an invocation-probe or control case or one tagged `no-network`; a without-arm run's network denials are not read
