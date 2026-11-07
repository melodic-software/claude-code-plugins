---
bump: patch
---

### Fixed

- `/visualization:present`'s deck check command takes `--option "<option>"` instead of the `${user_config.medium}` token, passing `""` when the option reads empty or unsubstituted, so an unsubstituted token never reaches the shell ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
