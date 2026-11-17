---
bump: patch
---

### Fixed

- The SessionStart prerequisite notices no longer name a plugin the session's `--settings` file turns off, such as one a plugin profile session leaves out. The prerequisite reader reads the file `SESSION_SETTINGS_FILE` names after the project-local settings and before managed ones; unset, or naming a missing or unreadable file, it adds nothing ([#16673](https://github.com/melodic-software/claude-code-plugins/issues/16673)).
