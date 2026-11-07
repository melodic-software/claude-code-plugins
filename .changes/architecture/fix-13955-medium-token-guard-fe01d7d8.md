---
bump: patch
---

### Fixed

- The `map-*` skills, `/architecture:improve` and the rendered-view reference pass `""` for the `medium` option when it reads empty or unsubstituted and never put a `${user_config.*}` string in a shell command ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
