---
bump: patch
---

### Fixed

- **The vault-exec recipe's MCP pointers reach real sections.** The tool-name and deduplication basis named headings that do not exist; it now points at the MCP page's plugin-provided servers and scope-precedence sections.
- **The vault-exec recipe's per-project `/mcp` disable step points at the section that records it.** Where `/mcp` stores a disabled-server choice is read from the MCP page's "Disable a server without removing it" section, not the scope-precedence section, which does not cover it.

### Changed

- **Restated Claude Code behavior in the README and `/miro:setup` becomes anchored pointer records.** Where sensitive option values are stored, when options are prompted for, the plugin CLI's scope defaults and flag spellings, and when Claude Code installs a plugin root's npm dependencies are read live. The setup bootstrap still passes the scope explicitly on every command; only its scope defaults and flag spellings are now read live instead of restated.
