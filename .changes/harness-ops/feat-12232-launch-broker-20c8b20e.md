---
bump: minor
---

### Added

- control-claude-code: a launch broker that runs the driver's `launch`, `ready` and `log` inside a sandbox for an unattended caller, and a driver broker mode (`CCD_BROKER_SOCK`) that sends those verbs to it. The driver reads `CCD_RUNTIME_DIR` ahead of `XDG_RUNTIME_DIR`.
