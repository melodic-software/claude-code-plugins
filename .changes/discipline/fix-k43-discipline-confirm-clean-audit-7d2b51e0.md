---
bump: patch
---

### Fixed

- The shared re-anchor method's step 2: on load-bearing work a clean self-audit is confirmed by a fresh-context subagent before the report calls it clean, governed by the `verification` level like step 3; under `light` and `off` the report says "clean (self-audit only)" with the skip token. The eight correctors that point at step 2 name the confirmation, and `/discipline:sweep-all` batched forks return "clean (unconfirmed)" for the main thread to confirm.
