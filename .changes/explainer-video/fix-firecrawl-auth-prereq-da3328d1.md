---
bump: patch
---

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.
