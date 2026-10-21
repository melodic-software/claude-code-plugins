---
bump: patch
---

### Changed

- The HIGH path floor rule and the `floor-paths` and `floor-script-scopes` descriptions say that a test file (a `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name, or a `tests/` or `fixtures/` directory) under a plugin `scripts/` directory, a `floor-paths` glob with a `scripts` segment or a script scope, safe and under no declared path, no longer holds a pull request for that reason; every other floor entry and `floor-paths` glob, and `denied-paths`, still do.
