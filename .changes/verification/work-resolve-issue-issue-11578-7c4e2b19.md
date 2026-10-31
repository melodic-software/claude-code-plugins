---
bump: patch
---

### Fixed

- `/verification:confirm` adds `--unattended` to its `/app-control:map refresh` call only when its own caller passed `--unattended`. A pipeline lane that omits the flag gets a refresh that may ask ([#11578](https://github.com/melodic-software/claude-code-plugins/issues/11578)).
