---
bump: patch
---

### Changed

- The interview skill's page-lane context records the saved-boolean substitution probe: on
  Claude Code 2.1.312 a saved boolean `true` substitutes into skill content, and an unset key with
  a `default` stays a literal token
  ([#6050](https://github.com/melodic-software/claude-code-plugins/issues/6050)).
