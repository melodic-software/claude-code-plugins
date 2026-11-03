---
bump: patch
---

### Changed

- `check-skill.sh` honors `PLUGIN_TEST_DEADLINE` in check 7: a script test not started by that time never starts and prints a `SKIP` line naming it. With no failure the run ends `INCOMPLETE` at exit 3, never `PASS`. With the variable unset, every script test runs as before.
