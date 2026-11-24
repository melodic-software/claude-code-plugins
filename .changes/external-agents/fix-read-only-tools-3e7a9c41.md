---
bump: patch
---

### Fixed

- `external-agents models <product>` now prints `read_only_tools`, the tools that still work under
  `--mode read-only`, from a new `harness.read_only_tools` list in each provider record (Codex:
  `file`, `shell`, `web`, `mcp`; Antigravity: `file`). A record with no list reports `tools`
  there. Before this, `tools` was the only view, so a router could send a read-only research brief
  to Antigravity, whose read-only runs refuse shell, web and MCP calls.
