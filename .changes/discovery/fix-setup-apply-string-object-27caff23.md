---
bump: patch
---

### Fixed

- The shared settings checker behind `/discovery:setup` validates string and object settings, and reports a setting whose schema shape it does not check instead of stopping with a JavaScript error.
