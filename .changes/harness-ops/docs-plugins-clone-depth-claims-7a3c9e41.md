---
bump: patch
---

### Fixed

- `/harness-ops:plugins` no longer states a marketplace clone depth or the `11 of 74` unverifiable example. The cache-content check and its context records now say the clone is shallow and re-cloned on update, that only installs recorded at a commit inside the clone can be compared, and that most installs read unverifiable after a refresh.
