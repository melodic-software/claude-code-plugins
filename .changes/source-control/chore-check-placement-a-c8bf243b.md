---
bump: patch
---

### Changed

- `/source-control:pull-request` prep runs the `/testing:audit --judge` pass over changed tests when the testing plugin is installed, and reports `judge pass not run: testing plugin not installed` otherwise.
