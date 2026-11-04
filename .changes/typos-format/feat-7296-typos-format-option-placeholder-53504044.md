---
bump: patch
---

### Fixed

- `setup check` tells the model to read option values from the rendered skill text and never put a `${user_config.*}` string in a shell command.
- `setup check` names `prerequisites.json` and the bundled config by their paths under the plugin root, so the model reads it instead of searching the plugin directory.
- `setup check` opens plugin files by the paths it names and never searches the plugin directory.
