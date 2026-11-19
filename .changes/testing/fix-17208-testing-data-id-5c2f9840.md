---
bump: patch
---

### Fixed

- `check-visual-parity`: outside a marketplace checkout and without `CLAUDE_PLUGIN_DATA`, `visual-compare.sh` installs under the data directory named from the install's own marketplace (`testing-<marketplace>`, or `testing-inline` outside the plugin cache) instead of one fixed publisher marketplace.
