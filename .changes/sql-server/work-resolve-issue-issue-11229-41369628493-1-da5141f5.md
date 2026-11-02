---
bump: patch
---

### Added

- The integration test (`integration/read-path.mjs`) checks the write tier against #5940's S4 requirement
  ([#11229](https://github.com/melodic-software/claude-code-plugins/issues/11229)). It creates a
  separate write login and runs the server twice, without `--write` and then with it. It checks
  that `write` carries `_meta["anthropic/requiresUserInteraction"]: true` and the other tools do
  not, and that `write` is refused without `--write`. With `--write`, it checks that a write
  that affects `expectedRows` rows commits and that one that affects more rows rolls back with a
  tool error.
  It also checks that `tools/list` is the same on both registrations.
