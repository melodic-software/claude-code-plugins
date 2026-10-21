---
bump: minor
---

### Added

- The audit adds `startup-items`, which lists everything that starts at logon (Run and RunOnce keys, Startup folders, logon tasks) with its Task Manager enabled state, and `app-last-use`, which lists installed apps with "no launch recorded since" the date the launch records begin; the startup inventory moves out of `services`.
