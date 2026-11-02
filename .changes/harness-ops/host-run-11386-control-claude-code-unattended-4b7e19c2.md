---
bump: minor
---

### Changed

- `control-claude-code` runs unattended as well as attended, on the session it launches only; it still never signs in, never attaches to a session it did not start, and never drives Claude Desktop. Ready still requires `apiKeySource` `none` on every run.
- The driver's launch sets `CLAUDE_CODE_HIDE_CWD=1`, so the startup screen in a capture does not show the working directory, and the config caps a run at `maxCaptures: 20` screenshots and videos.
