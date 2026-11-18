# Changelog

All notable changes to the `plugin-diagnostics` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.5] - 2026-11-18

### Security

- The shared hook::file_is_gitignored check runs git with core.fsmonitor and core.hooksPath turned off on the command line, through the new hook::git_untrusted helper, so a repository whose config names a command cannot make it run.

## [0.1.4] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [0.1.3] - 2026-11-17

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

## [0.1.2] - 2026-11-17

### Fixed

- The SessionStart prerequisite notices no longer name a plugin the session's `--settings` file turns off, such as one a plugin profile session leaves out. The prerequisite reader reads the file `SESSION_SETTINGS_FILE` names after the project-local settings and before managed ones; unset, or naming a missing or unreadable file, it adds nothing ([#16673](https://github.com/melodic-software/claude-code-plugins/issues/16673)).

## [0.1.1] - 2026-11-16

### Fixed

- "On by default" applies to a new install only: a marketplace update does not install plugin-diagnostics where the marketplace was already installed ([ADR 0109, probe row `default-on-existing-users`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0109-switch-plugin-sets-by-profile-and-gate-optional-calls-on-enabled-skills.md#probe-record-claude-code-21325-2026-11-15)). An existing install runs `claude plugin install plugin-diagnostics@melodic-software`. The README says the same.

## [0.1.0] - 2026-11-16

### Added

- The `plugin-diagnostics` plugin, on by default: reports why installed plugins cannot run. At the end of each turn it warns once per session per hook about a hook that failed to launch or exited non-zero without Claude Code showing it; at session start it says when `node` is missing and runs each enabled plugin's declared prerequisites probe, as one notice. These rows were harness-ops'; `hook_failure_audit_enabled` and `stdin_read_timeout` keep their names: set them again for `plugin-diagnostics@<marketplace>`.

### Changed

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.
