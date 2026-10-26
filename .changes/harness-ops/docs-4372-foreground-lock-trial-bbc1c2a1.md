---
bump: patch
---

### Changed

- **audit-performance:** the Token-leak reference now records the per-logon `ForegroundLockTimeout` workaround, applied after every logon because a third-party write-up reports that Windows resets the live value at logon; on the trial host a process that cannot take the foreground was refused the set. It also records the trial on one host and a before-baseline on build 26300.9711, where the leak still counts one token per creator.
