---
bump: minor
---

### Added

- The `plugin-diagnostics` plugin, on by default: reports why installed plugins cannot run. At the end of each turn it warns once per session per hook about a hook that failed to launch or exited non-zero without Claude Code showing it; at session start it says when `node` is missing and runs each enabled plugin's declared prerequisites probe, as one notice. These rows were harness-ops'; `hook_failure_audit_enabled` and `stdin_read_timeout` keep their names: set them again for `plugin-diagnostics@<marketplace>`.
