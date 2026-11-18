---
bump: patch
---

### Fixed

- `control-claude-code`: under `--real-setup`, the print-mode turns of the driver's `ready` and `log` keep `--strict-mcp-config`, so they connect no MCP server from the folder without a trust prompt. The interactive `launch --real-setup` session still drops both isolating flags.
