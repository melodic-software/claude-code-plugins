---
bump: minor
---

### Added

- `control-claude-code`: `--real-setup` on the driver's `launch`, `ready` and `log` starts Claude Code without `--restricted` and `--strict-mcp-config`, so a drive shows the plugin under test beside the person's own settings, plugins, hooks, MCP servers and status line. It runs only attended: the driver refuses it with `--unattended`, `--in-sandbox`, a kept credential, or through the launch broker. With it, `--launcher <word>`, once per word, runs a command such as `profiles.mjs start <profile>` in place of the bare `claude`, as an argument vector with no shell.
- `control-claude-code`: `## Mask` hides the status line's session id, cost and limit rows, and `## Gotchas` names the first-run dialogs a `--real-setup` session can show (folder trust, external CLAUDE.md imports, the auto-mode offer) with the answer to give each.
