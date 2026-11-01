---
bump: patch
---

### Fixed

- `diagnose` now says that a screensaver, display or power fix stays the operator's even when
  the operator asks the agent to apply it: the agent neither runs the change nor writes a script
  or `.reg` file that applies it, and names the setting and value to change instead.

Also adds outcome eval cases for the diagnose and setup skills and frozen trigger probes for
diagnose.
