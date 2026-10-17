---
bump: patch
---

### Changed

- The running-retro observer decodes transcript lines through the shared `transcript_reader.decode_line`, so it no longer carries its own JSONL decode; its events, `mid` tagging and turn-boundary rule are unchanged, and the status `parse_errors` count now includes non-object lines.
- `transcript_reader` gains `decode_line(line, stats)`, the one-line entry point `iter_records` is now built on.

### Fixed

- The observer's comment on bare strings in a user content list no longer claims the canonical parser counts them as human messages.
