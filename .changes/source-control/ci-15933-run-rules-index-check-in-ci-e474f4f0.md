---
bump: patch
---

### Changed

- `CARRY_REFUSES` lists `plugins/instruction-placement/scripts/**`, since this repository's `pr-require-checks.yml` now runs `render-index.sh` from it: a push touching that directory stops an approval carrying, the same as every other script a hold path runs ([#15933](https://github.com/melodic-software/claude-code-plugins/issues/15933)).
