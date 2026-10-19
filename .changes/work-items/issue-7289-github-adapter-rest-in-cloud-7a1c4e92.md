---
bump: patch
---

### Fixed

- The GitHub adapter reads and creates items over REST in Claude Code cloud sessions (`CLAUDE_CODE_REMOTE=true`) whatever the `gh` version, and retries a native read or create over REST when the proxy answers with its "GitHub GraphQL is not available from Claude Code sessions" 403. Sub-issue and dependency edges and the `blockedBy` listings, which have no REST form, now exit 3 with an "unavailable in this Claude Code cloud session" message instead of failing on a refused GraphQL call.
