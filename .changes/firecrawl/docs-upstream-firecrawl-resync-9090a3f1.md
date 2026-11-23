---
bump: patch
---

### Changed

- `/firecrawl:update`'s sync record moves to the current upstream `SKILL.md` (SHA256 `3a86fb35`), with CLI 1.30.0, still npm latest. The only upstream change since `b4d49850` drops the `POST /support/docs-search` endpoint, which the wrapper never used, so `/firecrawl:firecrawl` is unchanged.
