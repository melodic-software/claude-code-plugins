---
bump: minor
---

### Added

- **control-claude-code:** the control skill `/app-control:drive` reads to run Claude Code's terminal UI with a plugin loaded. Its hub names Launch, Ready, Capture (screenshot, video, and logs as stream-json) and Cleanup, marks it for attended runs only, and never signs in or switches accounts. `config/defaults.json` holds `pluginDir`. Feature folders cover a mod's band, toast and panel, skill invocation, hook output, slash commands, the permission dialog, and Claude Desktop through `claude plugin test`; every Claude Desktop entry point is `not driven: terms`.
- **control-claude-code driver:** two verbs that run Claude Code in print mode with the launch's flags and environment and write its stream-json to `--out`. `ready` prints doctor's lines, whether the session answers, and the init event's version, plugins and `apiKeySource`. It stops Claude Code once the init event arrives, and exits 1 unless `apiKeySource` is `none` and the init event lists the plugin under test. `log <prompt>` keeps the whole run, and stops Claude Code early when the init event names an API key. Both stop Claude Code and every process it started at `--timeout`.
