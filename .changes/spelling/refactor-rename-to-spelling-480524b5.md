---
bump: major
---

### Changed

- The plugin is now `spelling`: install it as `spelling@<marketplace>`, and its setup skill runs as `/spelling:setup`.
- The options are `spelling_enabled` and `spelling_end_of_turn`, with kill-switch variables `CLAUDE_PLUGIN_OPTION_SPELLING_ENABLED` and `CLAUDE_PLUGIN_OPTION_SPELLING_END_OF_TURN`. Saved values move to the new keys through the dotfiles rename map on the next converge; a machine not managed by that dotfiles repository sets them again.
- The git pre-commit entry installs under `.githooks/spelling/`, its decline key is `checks.spelling.typos-check.declined`, and its findings start with `spelling:`. In a repository that had the entry, `/spelling:setup check` reports what the earlier install left as `superseded`, and `/spelling:setup apply install-git-hooks` installs the entry, removes those artifacts on your yes and keeps an earlier decline under the new key.
