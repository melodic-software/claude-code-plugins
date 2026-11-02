---
bump: patch
---

### Added

- evals: `browser-mcp-probe`, an environment probe that drives Chromium through `@playwright/mcp` 0.0.83 from a case-local plugin, for the browser lane's MCP path (run with `allow-real-servers` and an `mcp__plugin_pw-mcp_playwright__*` grant; see the case README).
