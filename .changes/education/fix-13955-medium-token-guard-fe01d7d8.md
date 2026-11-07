---
bump: patch
---

### Fixed

- `/education:illustrate`'s medium resolver command takes `--option "<option>"` instead of the `${user_config.medium}` token, and `/education:teach` passes `""` for the `medium` option when it reads empty or unsubstituted, so an unsubstituted token never reaches the shell ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
