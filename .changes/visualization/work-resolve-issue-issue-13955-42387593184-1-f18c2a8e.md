---
bump: patch
---

### Fixed

- `/visualization:present`'s `check-deck.mjs` command takes `--option "<option>"` in place of the `${user_config.medium}` token, and the skill passes `""` when the `medium` option reads empty or unsubstituted, as `/visualization:visualize` already did ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
