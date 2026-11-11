---
bump: patch
---

### Changed

- `/harness-ops:changelog` reads a fired recheck trigger as a `correct` signal only for a stored value (a recorded default, limit, version gate or measured observation); for a pointer, which carries no trigger, the feature grep is the signal.
- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.
