---
bump: minor
---

### Added

- The lanes launcher reads a per-lane `profile` and starts that lane in the plugin profile through plugin-profiles, with the lane's `settings` merged into the profile's session file. A profile that needs a missing required tool skips that lane with an error, and `restart` checks that before stopping the running lane; with plugin-profiles not installed and enabled, or on a cloud-session lane, the lane launches without the profile and a warning says so. A restart through the restart consumer keeps the profile.

### Changed

- Every lane launch clears an inherited `PLUGIN_PROFILES_SESSION`, so a lane started from a profiled session's shell does not carry that session's profile.
