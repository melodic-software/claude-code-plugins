---
bump: minor
---

### Added

- `continue-in-background` starts the background session in the session's plugin profile when the plugin-profiles plugin is enabled, and the cloud launch report says the cloud session starts without it.
- `save_point.py new --settings-file <file>` puts `--settings "<file>"` on the handoff's `claude --resume` line; the handoff skill passes the file plugin-profiles gives it.
- A handoff whose next phase runs in another profile adds a line above the copy line (`save_point.py new --start-command`) telling the user to exit and start the next session with that profile's start command; the copy line itself is unchanged, so `/session-flow:find-handoff` still finds it.

### Changed

- The handoff's plugin profile restore entry is the "Start another session here in this profile with:" line from `/plugin-profiles:profile status`.
