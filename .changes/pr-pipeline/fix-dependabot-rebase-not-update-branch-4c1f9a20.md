---
bump: patch
---

### Fixed

- The pr-unblock dispatcher no longer sends resolve-conflicts to a Dependabot head (a `dependabot/` branch Dependabot opened): its merge commit stopped Dependabot's own rebases, which resolve the conflict.
