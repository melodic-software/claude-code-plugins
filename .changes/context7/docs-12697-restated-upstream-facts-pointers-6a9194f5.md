---
bump: patch
---

### Changed

- `lookup` and its MCP reference no longer list the MCP tools' parameters or describe them; they
  keep the tool-list check, the tool-to-CLI mapping and why the two transports are treated alike,
  and point at Context7's MCP Tools section.
- The Windows Git Bash gotcha keeps the rewrite it guards against and the `MSYS_NO_PATHCONV=1`
  prefix rule, and points at MSYS2's automatic path conversion section.
