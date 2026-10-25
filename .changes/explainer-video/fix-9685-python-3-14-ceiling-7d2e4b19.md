---
bump: patch
---

### Fixed

- `prerequisites.json` caps the `python` entry with `below: "3.14"`, so a host whose only Python is 3.14 is reported outdated instead of ready. The install hook runs only on Python 3.12 or 3.13.
