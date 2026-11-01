---
bump: patch
---

### Fixed

- work-item tracker: `list-frontier` now excludes any item carrying a label that starts `wayfind:`, in both the attended and the `--autonomous` frontier. `/work-items:work` no longer picks a wayfind map item, which `/planning:wayfind` drives (#11870).
