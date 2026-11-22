---
bump: patch
---

### Fixed

- The two mixer tests that drive the plugin through the test harness pass on a Windows host, where the harness hands `fs.write` the command-file path resolved there.
