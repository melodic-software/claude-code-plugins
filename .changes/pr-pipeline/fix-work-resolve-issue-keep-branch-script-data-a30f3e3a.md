---
bump: patch
---

### Fixed

- The issue lane's `run-checks` job keeps the base's check scripts but restores the lane branch's own `scripts/` data files (`.txt`, `.json`, `.jsonl`), so a check reads the lists the branch changed, such as a new plugin in `scripts/fragment-plugins.txt`, the same as the pull request's CI.
