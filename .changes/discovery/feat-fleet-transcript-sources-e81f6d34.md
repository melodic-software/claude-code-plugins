---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read.
- `turns-to-complete.py` markdown passes through a publish redactor over the `--sources-file` sources: host names become stable `<host-N>` placeholders, and usernames, IP addresses, emails, home paths and secrets typed ones. The plugin now vendors the gitleaks rules (`vendor/gitleaks/`) the redactor reads. A new `redact_identifiers` option, passed as `--redact-identifiers`, adds comma-separated names and paths to replace with `<identifier>`. A sources file that is missing or unusable, or secret rules that do not load, stop the output with exit 2 and nothing published.

### Changed

- `turns-to-complete.py` without `--root` reads the projects directory of each local source in `--sources-file` (unset, `CLAUDE_CONFIG_DIR`, else `~/.claude`), parses transcripts through the shared transcript reader, and opens its report with a header naming a source whose projects directory cannot be listed, with the command that retries it. `--diagnostics-dir` keeps that gap as a lookup diagnostics record. The header also names each source of the sources file on another host, which it does not read, so its counts are this host's only.
- A `transcript_sources_file` path, and a local source's `config_dir` in it, starting with `~` are read from the home directory; a missing sources file prints its warning once per run.
