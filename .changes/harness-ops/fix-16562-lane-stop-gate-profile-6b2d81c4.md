---
bump: patch
---

### Fixed

- A lane that arms the lane-stop gate under a plugin profile whose merged settings leave `autonomy` off is no longer launched without its gate: the launch refuses it with an error naming the lane, the profile and the fix, and `restart` checks that before stopping the running lane. A lane with no gate, or with no profile, launches as before.
