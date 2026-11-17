---
bump: minor
---

### Added

- An ecosystem record can declare what a command needs beyond its tool on `PATH` under the new `requires` key (ecosystem-commands contract 1.4.0), keyed by command key, and a gate under its own `requires`. Each entry has a `name`, a read-only `probe` whose exit 0 means present, and an optional `hint`. With any entry absent, `/toolchain:check` and `/toolchain:lint` do not run the command: its cell reads `skip (prerequisite missing: <name>)` and the Overall line reads `INCOMPLETE`, never `FAIL` from a crashed command or `PASS` from the wrong build of a tool. A probe that errors, cannot start or passes 30 seconds reads the same skip.

### Changed

- `/toolchain:check` installs missing lockfile dependencies only in an attended run. An unattended run (`CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop) installs nothing and reports `skip (dependencies missing: unattended run)`. Neither skill ever installs a declared prerequisite.
