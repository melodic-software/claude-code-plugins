---
bump: patch
---

### Fixed

- The `SessionStart` row no longer fails on every new session when `node` is not on `PATH`: it runs through `lib/node-or-skip.sh` and exits 0 silently, and harness-ops' node notice tells the user.
