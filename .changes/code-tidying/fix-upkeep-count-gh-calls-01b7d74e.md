---
bump: patch
---

### Fixed

- `open-pr-count.sh` counts its `gh pr list` call in this repository's CI job api-budget notice,
  through the shared gh wrapper; elsewhere it calls gh as before.
