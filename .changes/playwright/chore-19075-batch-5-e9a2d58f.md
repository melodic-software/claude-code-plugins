---
bump: patch
---

### Fixed

- `/playwright:playwright` no longer says `close-all` reaches every browser on the machine; it and its sessions reference point at upstream's Sessions section for the scope of `close-all` and `kill-all`, and at upstream's Installation section for the install command ([#19075](https://github.com/melodic-software/claude-code-plugins/issues/19075)).
