---
bump: patch
---

### Fixed

- **measure-invocation:** `emit-plugin-eval` now writes a `plugins:` line into each case that loads the target plugin and every competitor's plugin, so a description competes against its cross-plugin rivals instead of firing alone, and it exits 2 when a competitor's plugin directory is missing or the out-dir sits outside the repository root. The probe template now allows cross-plugin rivals in a set meant for live runs.
