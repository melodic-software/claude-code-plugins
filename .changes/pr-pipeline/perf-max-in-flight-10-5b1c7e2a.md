---
bump: patch
---

### Changed

- This repository's `merge.max-in-flight` rises from 5 to 10. One full run of main's tip verifies every lane merge it contains, so the lane arms up to twice as many pull requests per verification cycle with no extra full runs. A red run now charges up to 10 unverified lane merges, and any charge still demotes the rung.
