---
bump: patch
---

### Fixed

- `/session-flow:audit-friction` now lists every projects root it read in the report header. It also warns when a default run skipped a sibling projects tree on the same host: under WSL, a Windows user's tree under the drive mounts; on Windows, a running WSL distribution's tree. The warning names the path and the `--source` argument that adds it. A stopped WSL distribution is listed as unchecked and is never started.
