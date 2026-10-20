---
bump: patch
---

### Fixed

- `audit`: the effective-config line runs the detector alone, with no pipe into `head -40`, so it loads in a CI lane whose deny rules name `head`.
