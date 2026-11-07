---
bump: patch
---

### Fixed

- `/discovery:blindspot`'s medium resolver command takes `--option "<option>"` instead of the `${user_config.medium}` token, passing `""` when the option reads empty or unsubstituted, and the rendered-view reference carries the same rule ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
