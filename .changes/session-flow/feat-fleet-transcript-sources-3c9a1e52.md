---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read. `scripts/transcript_sources.py check FILE` validates a file, exiting 2 with the file named when it is malformed.
