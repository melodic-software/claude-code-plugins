---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read.
- `/performance:go-faster` reports (`findings.py render` and `finish`) pass through a publish redactor over the `--sources-file` sources: host names become stable `<host-N>` placeholders, and usernames, IP addresses, emails, home paths and secrets typed ones. The plugin now vendors the gitleaks rules (`vendor/gitleaks/`) the redactor reads. A new `redact_identifiers` option, passed as `--redact-identifiers`, adds comma-separated names and paths to replace with `<identifier>`. A sources file that is missing or unusable, or secret rules that do not load, stop the output with exit 2 and nothing published.

### Changed

- `/performance:go-faster` finds the session's transcript in every local source of the `transcript_sources_file`, quotes the resolver's warning about that file (not found, or refused) at the top of its reply, and its sweeper's `findings.py finish` receives the `transcript_sources_file` and `redact_identifiers` options for the publish redactor.
- `lib/publish.py` also runs as a command that redacts its input.
- A `transcript_sources_file` path, and a local source's `config_dir` in it, starting with `~` are read from the home directory; a missing sources file prints its warning once per run.
- The shared redactor copy (`redact.py`) can leave report field names its caller lists unredacted; this plugin lists none, so its redaction is unchanged.

### Fixed

- Redacting a secret at the end of a line no longer joins the next line onto the redacted one.
