---
bump: major
---

### Changed

- The plugin is now `spelling`: install it as `spelling@<marketplace>`, and its setup skill runs as `/spelling:setup`.
- The options are `spelling_enabled` and `spelling_end_of_turn`, with kill-switch variables `CLAUDE_PLUGIN_OPTION_SPELLING_ENABLED` and `CLAUDE_PLUGIN_OPTION_SPELLING_END_OF_TURN`. Both start at their defaults (`true` and `false`): set `spelling_enabled` to `false` to keep the hooks off, or `spelling_end_of_turn` to `true` to keep the end-of-turn check on.
- The git pre-commit entry installs under `.githooks/spelling/`, its decline key is `checks.spelling.typos-check.declined`, and its findings start with `spelling:`. Run `/spelling:setup apply install-git-hooks` in each repository that had the entry.
