---
bump: minor
---

### Added

- control-claude-code: `launch`, `ready` and `log` take an opt-in `--real-setup` that drops `--restricted` and `--strict-mcp-config`, so a drive loads the person's installed plugins, hooks, permission rules and status line beside the plugin under test. Repeated `--launcher <word>` starts the session through a launcher (such as `profiles.mjs start <profile>`) in place of the bare `claude`. Both are refused with `--unattended` and `--in-sandbox`, and the brokered path refuses them too. Captures also mask a status line's session id, cost and usage-limit percentages ([#16997](https://github.com/melodic-software/claude-code-plugins/issues/16997)).
