---
bump: patch
---

### Fixed

- `setup check` tells the model to read option values from the rendered skill text and never put a `${user_config.*}` string in a shell command. Its Bash step now says the hook documents no version floor, instead of pointing at the README.
- `setup check` names `prerequisites.json` by its path under the plugin root, so the model reads it instead of searching the plugin directory.
