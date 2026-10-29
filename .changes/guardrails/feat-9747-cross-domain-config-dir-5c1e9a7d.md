---
bump: minor
---

### Added

- `block-cross-domain` now checks the `gh` and `az` config directory of a Bash or PowerShell call made from a session whose directory is in an identity domain ([#9747](https://github.com/melodic-software/claude-code-plugins/issues/9747)). When the domain has a `gh_config_dir`, a `gh` call that does not run with it is denied, whether the command sets `GH_CONFIG_DIR` or the hook's own environment carries it. When the domain has none, a `gh` call that runs with another domain's directory is denied. `az` is judged the same way with `AZURE_CONFIG_DIR` and `az_config_dir`. `gh --version` and `az --version` are exempt, and from a session outside every domain nothing is denied. A denied call starts no process, and the guard still exits 0 on every call.
