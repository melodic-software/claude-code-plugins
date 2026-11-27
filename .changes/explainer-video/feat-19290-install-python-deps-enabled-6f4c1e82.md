---
bump: minor
---

### Added

- `install_python_deps_enabled` option (boolean, default `false`) in `plugin.json` and `schemas/explainer-video.schema.json` controls the SessionStart `install-python-deps` hook across the plugin default, user layer (`CLAUDE_PLUGIN_OPTION_INSTALL_PYTHON_DEPS_ENABLED`), and repository layer (`docs/conventions/explainer-video.yaml`) through `lib/hook-enabled.sh`.

### Changed

- The SessionStart `install-python-deps` hook now defaults to off per the hook-enablement convention because it installs packages over the network without an explicit request; running `/explainer-video:produce` without the packages prints the one-line install command.
