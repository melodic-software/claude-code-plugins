---
bump: patch
---

### Fixed

- **The `firecrawl-api-key` prerequisite is now `optional`**, so `/harness-ops:prerequisites` no longer reports the firecrawl skill blocked when `FIRECRAWL_API_KEY` is absent from the Claude Code environment but the CLI is authenticated another way (a wrapper that injects the key into the CLI process only, or `firecrawl login`). Its degrade line names `firecrawl --status` as the real auth test, which `/firecrawl:setup` already treats as authoritative; the README requirement says the same.
