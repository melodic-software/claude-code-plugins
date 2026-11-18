# Changelog

All notable changes to the `session-telemetry` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.5] - 2026-11-18

### Security

- The shared hook::file_is_gitignored check runs git with core.fsmonitor and core.hooksPath turned off on the command line, through the new hook::git_untrusted helper, so a repository whose config names a command cannot make it run.

## [0.1.4] - 2026-11-17

### Fixed

- `measure-hook-log-budget.sh` waits on each parallel hook row and append job by pid and exits 3 when one fails, instead of timing a failed run into `parallel_wall_*` or reporting a short append line count.

## [0.1.3] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [0.1.2] - 2026-11-17

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

## [0.1.1] - 2026-11-17

### Fixed

- With `session_event_log_categories` set, the session event log's hooks module registers only the events in those categories, plus `SessionEnd` for retention, so an event outside them starts no process. Where the built-in guard `sec-default` holds `classic.*` events, it now holds only the events you chose. `SessionEnd` writes its record only when `session` is listed. The README says where the guard loads and which administrator actions let the log run there.

## [0.1.0] - 2026-11-16

### Added

- The `session-telemetry` plugin, off by default: the session-wide recorder harness-ops carried. Eight `*-audit` rows emit the hook-telemetry envelope for API errors, config changes, instruction loads, permission denials, compactions, tool failures and skill use (the Skill tool and slash-command expansion); the reference sink writes the hook log root; the hooks module keeps the default-off per-session hook event log and its SessionEnd retention. Its options are the ones those hooks had in harness-ops, under the same names: set them again for `session-telemetry@<marketplace>`.
- `HOOK_TELEMETRY_SINK=@session-telemetry` resolves to the launcher this plugin keeps in its data directory; `@harness-ops` resolves to the same launcher, so existing wiring keeps working.
- `skill-usage.jsonl` is size-capped: past the new `skill_usage_max_bytes` option (default 10485760) it moves to `skill-usage.jsonl.1`, replacing any older `.1`, the rule `hook-events.jsonl` follows. A store at the repo root (`skill_usage_dir=.`) keeps the store, its `.1` and its `.lock` out of `git status`. A writer that waits 2 s for the store's lock without getting it appends the row unlocked instead of dropping it.
- At each session start the plugin writes `options.json` in its data directory, the options its hooks run with, so a skill in another plugin can find the records (`docs/contracts/session-telemetry-data`).

### Changed

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.
