---
bump: patch
---

### Changed

- `/multi-agent:assess` now also returns a workflow verdict when the work needs independent agents to check each other's findings before they are reported.

### Fixed

- The fan-out guard's docs and `/multi-agent:route` say what the resolver emits instead of promising where an agent runs, and point at the upstream sections that decide it. The `mechanical` workload's `sonnet` default is recorded as this repository's judgment; the value is unchanged.
