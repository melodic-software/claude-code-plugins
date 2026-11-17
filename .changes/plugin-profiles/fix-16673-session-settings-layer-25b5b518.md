---
bump: patch
---

### Fixed

- A one-session file sets `SESSION_SETTINGS_FILE` to its own path, so plugin-diagnostics and harness-ops skip the prerequisite notices of plugins the profile turns off, and `launch` clears an inherited one ([#16673](https://github.com/melodic-software/claude-code-plugins/issues/16673)).
