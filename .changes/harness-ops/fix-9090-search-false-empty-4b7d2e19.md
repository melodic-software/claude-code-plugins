---
bump: patch
---

### Fixed

- `/harness-ops:morning-brief`: a queue count or stuck label whose search reads 0 is checked against the REST issue listing, which does not go through search ([#9090](https://github.com/melodic-software/claude-code-plugins/issues/9090)). When that listing reads more than 0 or fails, the label shows `count unavailable` on a `PARTIAL` line, and the Stuck section prints no all-clear.
- `/harness-ops:lanes` restart consumer: the `Lane telemetry: <lane>` issue lookup reads REST `search/issues` and treats an answer whose `incomplete_results` is not `false` as a failed read, so the lane records `api-error` instead of `no-telemetry` when search is degraded ([#9090](https://github.com/melodic-software/claude-code-plugins/issues/9090)).
