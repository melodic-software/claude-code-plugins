---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read. `scripts/transcript_sources.py check FILE` validates a file, exiting 2 with the file named when it is malformed.

### Fixed

- Redacting a secret at the end of a line no longer joins the next line onto the redacted one.
- An unset `audit_sessions_retention_days` option now applies its documented floor: 180 days raised to the longest `cleanupPeriodDays` of the sources read. A declared default had made the option always read as set.
