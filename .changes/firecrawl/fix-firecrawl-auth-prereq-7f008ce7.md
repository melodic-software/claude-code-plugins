---
bump: patch
---

### Fixed

- **The auth prerequisite now asks the CLI instead of the session environment.** The `firecrawl-api-key` env entry is replaced by a required `firecrawl-auth` entry that passes when `firecrawl --status` reports Authenticated, the test `/firecrawl:setup` already treats as authoritative. `/harness-ops:prerequisites` no longer reports the firecrawl skill blocked when `FIRECRAWL_API_KEY` is absent from the Claude Code environment but the CLI is authenticated another way (a wrapper that injects the key into the CLI process only, or `firecrawl login`), and still fails when the CLI is unauthenticated. The README requirement says the same.

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5,** so `firecrawl --status` behind a key-injecting wrapper (a secret lookup plus two API calls) no longer false-fails on a slow run. A hung probe now costs at most 20 seconds per entry.
