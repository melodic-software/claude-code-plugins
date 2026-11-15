---
bump: patch
---

### Changed

- `CARRY_REFUSES` lists `plugins/app-control/scripts/**`, since this repository's `pr-verify-capture.yml` now runs `affected_features.py` from it: a push touching that directory stops an approval carrying, the same as every other script a hold path runs ([#16184](https://github.com/melodic-software/claude-code-plugins/issues/16184)).
