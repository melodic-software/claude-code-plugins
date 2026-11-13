---
bump: major
---

### Changed

- The plugin is now `javascript-format`: install it as `javascript-format@<marketplace>`, and its setup skill runs as `/javascript-format:setup`.
- The options are `javascript_format_enabled`, `javascript_format_lint_gitignored` and `javascript_format_end_of_turn`, with kill-switch variables `CLAUDE_PLUGIN_OPTION_JAVASCRIPT_FORMAT_ENABLED`, `CLAUDE_PLUGIN_OPTION_JAVASCRIPT_FORMAT_LINT_GITIGNORED` and `CLAUDE_PLUGIN_OPTION_JAVASCRIPT_FORMAT_END_OF_TURN`. Saved values move to the new keys through the dotfiles rename map on the next converge; a machine not managed by that dotfiles repository sets them again.
- The git pre-commit entry installs under `.githooks/javascript-format/`, its decline key is `checks.javascript-format.biome-check.declined`, and its findings start with `javascript-format:`. In a repository that had the entry, `/javascript-format:setup check` reports what the earlier install left as `superseded`, and `/javascript-format:setup apply install-git-hooks` installs the entry, removes those artifacts on your yes and keeps an earlier decline under the new key.
