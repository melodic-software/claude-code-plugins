---
bump: minor
---

### Added

- `block-cross-domain` now applies the config directory rule ([#9747](https://github.com/melodic-software/claude-code-plugins/issues/9747)). In a domain whose map entry names a `gh_config_dir` or `az_config_dir`, a `gh` or `az` call is denied unless `GH_CONFIG_DIR` or `AZURE_CONFIG_DIR` is that directory, whether the command sets it or the hook's own environment holds it. In a domain that names no directory for the tool, a call that uses another domain's directory is denied. `gh --version` and `az --version` are exempt, and a neutral cwd is not checked. A deny is a stdout `permissionDecision` with exit 0, and it starts no process.
