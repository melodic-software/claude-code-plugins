---
bump: minor
---

### Added

- `skills/control-claude-code/driver/driver.mjs`, a terminal driver for Claude Code's TUI with the verbs `launch`, `wait-for`, `type`, `screenshot`, `record start|stop`, `stop` and `doctor`. `launch` starts `claude --restricted --strict-mcp-config --plugin-dir <dir>` with the API-key, auth-token and cloud-provider variables cleared, no `--bare`, and `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1`. On first use it installs the exactly pinned `@microsoft/tui-test` from the committed lockfile with `npm ci --ignore-scripts` into the plugin data directory and runs `npm audit signatures` once, failing closed with a repair line.
- An optional `noto-sans-symbols-2` font prerequisite probed with `fc-list`; without `fc-list` (macOS, Windows) `doctor` reports the font as unverified and capture proceeds.
