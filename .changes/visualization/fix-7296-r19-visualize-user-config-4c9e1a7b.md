---
bump: patch
---

### Fixed

- `visualize` passes the `medium` option to the medium resolver as the value read from the skill text, and never puts a `${user_config.*}` string in a shell command.
