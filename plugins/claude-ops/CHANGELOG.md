# Changelog

All notable changes to the `claude-ops` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.11.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's audit hooks. README now states the hook
  runtime (Bash via Git Bash on native Windows, jq) and the jq fail-open
  behavior.

## [0.11.0]

### Changed

- **Per-hook kill switches migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling). Each audit hook's toggle is now a `userConfig`
  boolean (default `true`), read by the hooks through the native
  `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror: `api_error_audit_enabled`,
  `config_change_audit_enabled`, `instructions_loaded_audit_enabled`,
  `permission_denied_audit_enabled`, `pre_compact_audit_enabled`,
  `skill_usage_audit_enabled` (shared by both skill-usage audit hooks), and
  `tool_failure_audit_enabled`. The `instructions-loaded-audit` session_start
  opt-in is now the `instructions_loaded_audit_log_session_start` option
  (default `false`), and the stdin read bound is the `stdin_read_timeout` option
  (default `2`). Configure interactively with `/plugin configure claude-ops` or
  headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED` and
  `HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START` environment variables are
  retired and no longer read. A consumer that set any of these in a settings
  `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all audit hooks on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.

## [0.10.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.10.0]

### Changed

- **Breaking:** renamed the `troubleshoot` skill to `known-issues` (plugin ID `claude-ops` is
  unchanged). Update any old invocations: `/claude-ops:troubleshoot` → `/claude-ops:known-issues`.
  The skill looks up and tracks known upstream Claude product issues; it never diagnoses or fixes
  local problems, so the old name over-promised. Behavior, actions, and the `registry_dir` option
  are unchanged; the registry is now referred to as the known-issues registry.

## [0.9.0]

### Added

- New `plugins` skill (`/claude-ops:plugins`): brings a machine's plugin fleet current on demand.
  `sync` (default) refreshes marketplaces, updates in-repo project/local-scope installs plus the
  user-scope sweep, installs new catalog plugins per the `install_new` policy, and fills any
  `enabledPlugins` completeness gap — all CLI-mediated, never hand-editing Claude Code's internal
  state files. `audit` runs the same algorithm read-only. `converge` is the one action that can
  touch a committed `.claude/settings.json`: it detects actionable (version-behind) scope
  divergence, previews and confirms per plugin, then surfaces the resulting diff for review — never
  auto-committed, and it aborts outright in an autonomous session. Adds a read-only
  `scripts/fleet-state.sh` state-inspection script and the `install_new` userConfig scalar
  (`ask` default / `all` / `none`).

## [0.8.0]

### Changed

- Rewired OTEL retention to stop, poll, and start the provisioning-owned `otelcol-contrib`
  Windows service. A failed stop or status query aborts before mutation; the prune lock remains
  held through restart, and a failed restart is visible to the caller.

### Removed

- Removed the duplicate Collector configuration and the private/public `start-collector.sh`
  process launchers. Machine provisioning is now the sole Collector lifecycle and configuration
  owner.

## [0.7.0]

### Changed

- Moved long-running telemetry lifecycle to machine provisioning: the boot-time
  `otelcol-contrib` Windows service owns collection, and the provisioning Compose stack owns the
  optional Aspire dashboards.

### Removed

- Removed the private and public `start-dashboard.sh` entry points and their tests. Claude
  sessions no longer create or replace machine-owned dashboard containers.

## [0.6.0]

### Changed

- Renamed three skills (plugin ID `claude-ops` is unchanged, only the leaf names moved). Update any
  old invocations:
  - `claude-observability` → `observability` (`/claude-ops:observability`)
  - `claude-troubleshooting` → `troubleshoot` (`/claude-ops:troubleshoot`)
  - `claude-code-changelog` → `changelog` (`/claude-ops:changelog`)
