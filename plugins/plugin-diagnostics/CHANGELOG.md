# Changelog

All notable changes to the `plugin-diagnostics` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1] - 2026-11-16

### Fixed

- "On by default" applies to a new install only: a marketplace update does not install plugin-diagnostics where the marketplace was already installed ([ADR 0109, probe row `default-on-existing-users`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0109-switch-plugin-sets-by-profile-and-gate-optional-calls-on-enabled-skills.md#probe-record-claude-code-21325-2026-11-15)). An existing install runs `claude plugin install plugin-diagnostics@melodic-software`. The README says the same.

## [0.1.0] - 2026-11-16

### Added

- The `plugin-diagnostics` plugin, on by default: reports why installed plugins cannot run. At the end of each turn it warns once per session per hook about a hook that failed to launch or exited non-zero without Claude Code showing it; at session start it says when `node` is missing and runs each enabled plugin's declared prerequisites probe, as one notice. These rows were harness-ops'; `hook_failure_audit_enabled` and `stdin_read_timeout` keep their names: set them again for `plugin-diagnostics@<marketplace>`.

### Changed

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.
