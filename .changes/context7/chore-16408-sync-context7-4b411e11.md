---
bump: patch
---

### Changed

- Synced `/context7:lookup` to `upstash/context7@17839096`: refreshed `vendor/find-docs/SKILL.md`, moved versioned lookups to `ctx7 docs --tag <version>` (probed via `ctx7 docs --help` with fallback for older installs) and MCP `query-docs`'s `version` input, and re-verified `context/cli.md` and `context/mcp.md` against `ctx7` 0.13.1 (adding `ctx7 code`, `ctx7 get-upgrade-guide`, `CONTEXT7_BASE_URL`, and updating the MCP API-key header snippet to `Authorization: Bearer`).
