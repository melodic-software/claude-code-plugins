---
bump: patch
---

### Fixed

- `babysit-prs`: a Merge run's gate processes serve a shared run-artifacts read only when it holds a FAIL, the only kind they store; a stored set without one is read again from GitHub.
