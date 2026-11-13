---
bump: major
---

### Changed

- The plugin is now `python-format`: install it as `python-format@<marketplace>`, and its setup skill runs as `/python-format:setup`.
- The options are `python_format_enabled`, `python_format_lint_gitignored` and `python_format_end_of_turn`, with kill-switch variables `CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_ENABLED`, `CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_LINT_GITIGNORED` and `CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_END_OF_TURN`. Saved values move to the new keys through the dotfiles rename map on the next converge; a machine not managed by that dotfiles repository sets them again, and repeats any opt-out it had: `python_format_enabled` set to `false`, or the plugin disabled, now under `python-format@<marketplace>`.
- The git pre-commit entry installs under `.githooks/python-format/`, its decline key is `checks.python-format.ruff-check.declined`, and its findings start with `python-format:`. In a repository that had the entry, `/python-format:setup check` reports what the earlier install left as `superseded`, and `/python-format:setup apply install-git-hooks` installs the entry, removes those artifacts on your yes and keeps an earlier decline under the new key.
