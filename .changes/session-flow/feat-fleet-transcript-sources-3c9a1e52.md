---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read. `scripts/transcript_sources.py check FILE` validates a file, exiting 2 with the file named when it is malformed.

### Fixed

- Redacting a secret at the end of a line no longer joins the next line onto the redacted one.
- An unset `audit_sessions_retention_days` option now applies its documented floor: 180 days raised to the longest `cleanupPeriodDays` of the sources read. A declared default had made the option always read as set.
- `/session-flow:recall` prints a history-only prompt only when its project is one of the scanned directories; a prompt from another project needs `--scope all`, which the skill passes only at the `all` scope.
- `/session-flow:audit-sessions` churn findings show a file edited outside the session's working directory at its own path, instead of joining its redacted `~/` form onto the working directory.
- `/session-flow:audit-sessions` published reports keep its metric names and drift canary keys, such as `cache.missed_input_tokens`, instead of replacing them with `<redacted:generic-api-key>`; a secret beside them is still redacted.
- A secret whose gitleaks rule marks only part of it, such as a base64 JWT, a Teams webhook URL or a Kubernetes Secret's later data values, is redacted whole; only line breaks and a trailing quote, space or semicolon are kept.
