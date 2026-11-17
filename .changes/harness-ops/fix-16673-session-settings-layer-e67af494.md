---
bump: patch
---

### Fixed

- `/harness-ops:prerequisites` and the session-telemetry state reader treat a plugin the session's `--settings` file turns off as off when `SESSION_SETTINGS_FILE` names that file, agreeing with the plugin-diagnostics SessionStart notices; the prerequisites table then reads settings files instead of `claude plugin list`, which does not see the file. Lane launches clear an inherited `SESSION_SETTINGS_FILE` ([#16673](https://github.com/melodic-software/claude-code-plugins/issues/16673)).
