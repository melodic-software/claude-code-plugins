---
bump: major
---

### Removed

- The `/plugin-quality:audit arm` entry. The session-flow observer runs by itself when session-flow's `observer_enabled` is on, so `arm` now launches nothing and says so.
