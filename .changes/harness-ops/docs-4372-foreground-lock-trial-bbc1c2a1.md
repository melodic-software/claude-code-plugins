---
bump: patch
---

### Changed

- **audit-performance:** the Token-leak reference now records the per-logon `ForegroundLockTimeout` workaround: Windows resets the live value at every logon, and a process that cannot take the foreground is refused the set. It also records the trial on one host and a before-baseline on build 26300.9711, where the leak still counts one token per creator.
