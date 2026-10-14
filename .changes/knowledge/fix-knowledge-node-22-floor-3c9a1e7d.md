---
bump: patch
---

### Fixed

- The prerequisites check now requires Node 22 or newer, so Node 21.0 and 21.1, which lack `import.meta.dirname`, no longer pass; Node 20 and 21 are past end of life ([#6922](https://github.com/melodic-software/claude-code-plugins/issues/6922)).
