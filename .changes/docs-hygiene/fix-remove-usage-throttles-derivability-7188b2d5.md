---
bump: patch
---

### Fixed

- `/docs-hygiene:audit-derivability` sweeps no longer cap concurrency at 3-4 for rate-limit headroom; the runtime's cap applies, and the skill backs off only on an actual rate-limit error.
