---
bump: patch
---

### Fixed

- A lane that arms the lane-stop gate under a plugin profile is checked before the gate is armed, so a `start` refused for leaving `autonomy` off no longer leaves an armed gate and a session file behind.
- The check requires the `autonomy` plugin id the lane's gate request is keyed under to be enabled; an `autonomy` plugin from another marketplace no longer passes it.
