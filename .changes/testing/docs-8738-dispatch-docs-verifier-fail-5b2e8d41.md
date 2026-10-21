---
bump: patch
---

### Fixed

- The `test_guards_enabled` option description said the hook asks for a reason. It adds an advisory note, and denies an added skip or removed test block only under `rules: {test-weaken-block: error}`; it never asks.
