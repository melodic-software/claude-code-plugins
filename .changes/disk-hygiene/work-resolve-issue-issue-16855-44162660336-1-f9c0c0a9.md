---
bump: patch
---

### Changed

- `/disk-hygiene:setup` confirms the plugin is enabled with `claude plugin list`, pointing at its docs section, in place of the `/plugin` panel path. `/disk-hygiene:clean` keeps its live-scratchpad rule, the electron-updater hint and the reversible-removal disclosure, but no longer restates the Claude Code temp-root layout (it points at the environment variables page), the electron-builder version gate, or the specific conditions that make a recycle permanent, now named only as the volume, the bin's settings or a policy ([#16855](https://github.com/melodic-software/claude-code-plugins/issues/16855)).
