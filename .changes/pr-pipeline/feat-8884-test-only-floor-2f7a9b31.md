---
bump: patch
---

### Changed

- The HIGH path floor rule and the `floor-script-scopes` description say that a test file (a `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name, or a `tests/` or `fixtures/` directory) under a plugin `scripts/` directory or a script scope, safe and under no declared path, no longer holds a pull request for that reason; every other floor entry, `denied-paths` and `floor-paths` still do.
