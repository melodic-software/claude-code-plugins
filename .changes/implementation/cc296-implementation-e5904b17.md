---
bump: patch
---

### Fixed

- **A worker's background CI wait survives the background time limit.** Where the Monitor tool is unavailable, `implementer` and `scoped-implementer` wait on CI or a long command with Bash `run_in_background`. That wait now passes an explicit `timeout`, so a long CI run in an unattended session (`-p`, the Agent SDK, CI, cloud) is started again on the stop notice instead of ending at the limit. Both agents point at the tools reference section on background time limits.
