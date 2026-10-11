---
bump: patch
---

### Fixed

- **The WebFetch truncation hook fires again on current Claude Code.** WebFetch now ends a result for a page over its read cap with its own read-on note, which the hook did not recognize, so every long-page truncation went unflagged. The hook now matches that note as well as the older markers, and for it the added context line says to call WebFetch again with the same URL and the offset the note names, with `/discovery:read-docs` as the other route.

### Changed

- **The research-sweep fetch and stage agents start without CLAUDE.md files.** `discovery:docs-fetcher` and `discovery:sweep-worker` set `omitClaudeMd: true`, so a one-fetch or web-only stage over untrusted pages no longer loads the user and project instruction hierarchy and follows only its workflow prompt.
