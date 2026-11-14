---
bump: minor
---

### Changed

- Intake admission no longer refuses, parks or adds `host-run` to an issue because its body or a done-when item names a path the issue lane cannot push, such as a workflow, `CODEOWNERS`, `.gitmodules` or a path Claude Code protects. A mention in prose or in a criterion that changes no such file had refused fixes the lane could build. A run whose change does need such a path still stops with `patch-protected-path`, which `stop-routes.json` routes to `host-run`.
