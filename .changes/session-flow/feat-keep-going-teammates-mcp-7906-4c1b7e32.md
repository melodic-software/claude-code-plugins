---
bump: minor
---

### Added

- `keep-going` now accounts for agent-team teammates and in-flight MCP calls after a stop. It reads a prior session's team task list when one exists and reports each task's last recorded status (or `none recorded`), and reports an MCP call as not observable with the reason, instead of skipping either kind silently. The shared `off-thread-work.md` reference lists both kinds, each with a pointer, as-of date and recheck trigger, and a new `keep-going` eval covers the case ([#7906](https://github.com/melodic-software/claude-code-plugins/issues/7906)).
