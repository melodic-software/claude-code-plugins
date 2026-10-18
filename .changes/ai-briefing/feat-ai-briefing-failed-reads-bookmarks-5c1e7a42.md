---
bump: minor
---

### Added

- `/ai-briefing:generate` gives every source one state in the briefing: `data`, `empty`, or `unreadable` (with the cause). An unreadable source is never shown as a quiet day.
- With no `--since`, each source reads back to its own bookmark under `${CLAUDE_PLUGIN_DATA}/<profile>/bookmarks/`, managed by the new `lib/source-bookmarks.sh`. A bookmark advances only after a full read of its source, so an unreadable or partial read leaves it unchanged. An explicit `--since` keeps the one fixed window and ignores the bookmarks.
- The skill frames fetched pages, feeds, and user URLs as data, reports an embedded instruction instead of following it, and names its three lethal-trifecta legs (private data, untrusted text, an outbound channel) and the leg it cuts: the outbound channel.
- Eval cases for a disabled source, bookmark versus `--since`, and an instruction in a fetched page.
