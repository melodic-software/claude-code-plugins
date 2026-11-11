---
bump: patch
---

### Changed

- `/docs-hygiene:audit-derivability` treats a pointer as its own drift control and never asks for an as-of date or recheck trigger on one, a `convert-to-pointer` result included; a recorded recheck trigger stays drift control for a cache.
- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.
