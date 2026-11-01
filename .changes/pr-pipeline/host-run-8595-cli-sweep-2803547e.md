---
bump: minor
---

### Added

- **A Claude Code CLI release procedure for the write lanes' shell deny set.** The README's new "Claude Code CLI releases" section says the lanes run the latest CLI and that a host sweeps each new CLI release and each claude-code-action bump with a live `dontAsk` run against a planted environment variable, adding any command that prints it to `shell_denied`. The comment above `shell_denied` names the last swept version (2.1.316, no command found).
